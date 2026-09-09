import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_environment.dart';

typedef ImOutboxDirectoryLoader = Future<Directory> Function();

const _imOutboxSyntheticPrefix = 'local-outbox:';

String imOutboxSyntheticFileId(String clientMessageId, String token) =>
    '$_imOutboxSyntheticPrefix$clientMessageId:$token';

({String clientMessageId, String token})? parseImOutboxSyntheticFileId(
  String value,
) {
  if (!value.startsWith(_imOutboxSyntheticPrefix)) return null;
  final payload = value.substring(_imOutboxSyntheticPrefix.length);
  final separator = payload.indexOf(':');
  if (separator <= 0 || separator == payload.length - 1) return null;
  return (
    clientMessageId: payload.substring(0, separator),
    token: payload.substring(separator + 1),
  );
}

final class ImOutboxStoredFile {
  const ImOutboxStoredFile({
    required this.token,
    required this.role,
    required this.fileName,
    required this.contentType,
    required this.length,
    required this.sha256,
    this.width,
    this.height,
  });

  factory ImOutboxStoredFile.fromJson(Map<String, Object?> json) =>
      ImOutboxStoredFile(
        token: json['token']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? '',
        contentType: json['contentType']?.toString() ?? '',
        length: _outboxInteger(json['length']),
        sha256: json['sha256']?.toString() ?? '',
        width: _outboxNullableInteger(json['width']),
        height: _outboxNullableInteger(json['height']),
      );

  final String token;
  final String role;
  final String fileName;
  final String contentType;
  final int length;
  final String sha256;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {
    'token': token,
    'role': role,
    'fileName': fileName,
    'contentType': contentType,
    'length': length,
    'sha256': sha256,
    'width': width,
    'height': height,
  };
}

/// Account-scoped, authenticated storage for queued IM binary payloads.
///
/// SQLite stores only encrypted metadata and opaque tokens. File names and
/// clear bytes never appear in paths. New files use independently
/// authenticated chunks so large payloads can be decrypted without buffering
/// the complete file. Legacy v1 files remain readable:
///
/// v1: `magic | clear length | nonce | cipher text | MAC`
/// v2: `magic | clear length | chunk size | base nonce | (cipher | MAC)*`
final class ImOutboxFileStore {
  ImOutboxFileStore({
    required this._keyLoader,
    ImOutboxDirectoryLoader? directoryLoader,
  }) : _directoryLoader = directoryLoader ?? _defaultDirectory;

  static final Uint8List _magicV1 = Uint8List.fromList(
    ascii.encode('IMOBX001'),
  );
  static final Uint8List _magicV2 = Uint8List.fromList(
    ascii.encode('IMOBX002'),
  );
  static const int _lengthBytes = 8;
  static const int _chunkSizeBytes = 4;
  static const int _clearChunkSize = 256 * 1024;

  final Future<List<int>> Function(String accountId) _keyLoader;
  final ImOutboxDirectoryLoader _directoryLoader;
  final Cipher _algorithm = AesGcm.with256bits();
  final Map<String, Future<SecretKey>> _keys = {};

  int get _v1HeaderLength =>
      _magicV1.length + _lengthBytes + _algorithm.nonceLength;

  int get _v2HeaderLength =>
      _magicV2.length + _lengthBytes + _chunkSizeBytes + _algorithm.nonceLength;

  Future<ImOutboxStoredFile> writeBytes({
    required String accountId,
    required String clientMessageId,
    required String role,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
    int? width,
    int? height,
  }) => writeStream(
    accountId: accountId,
    clientMessageId: clientMessageId,
    role: role,
    fileName: fileName,
    contentType: contentType,
    clearLength: bytes.lengthInBytes,
    source: Stream<List<int>>.value(bytes),
    width: width,
    height: height,
  );

  Future<ImOutboxStoredFile> writeStream({
    required String accountId,
    required String clientMessageId,
    required String role,
    required String fileName,
    required String contentType,
    required int clearLength,
    required Stream<List<int>> source,
    int? width,
    int? height,
  }) async {
    if (accountId.trim().isEmpty || clientMessageId.trim().isEmpty) {
      throw ArgumentError('Outbox file identity is required.');
    }
    if (clearLength <= 0) throw ArgumentError('Outbox file must not be empty.');
    final token = _newToken();
    final target = await _file(accountId, token);
    final temporary = File('${target.path}.tmp');
    final baseNonce = _algorithm.newNonce();
    final sink = temporary.openWrite();
    crypto.Digest? digest;
    final digestOutput = ChunkedConversionSink<crypto.Digest>.withCallback(
      (values) => digest = values.single,
    );
    final digestInput = crypto.sha256.startChunkedConversion(digestOutput);
    var digestClosed = false;
    var observedLength = 0;

    try {
      sink.add(_v2Header(clearLength, baseNonce));
      final key = await _key(accountId);
      final pending = BytesBuilder(copy: false);
      var chunkIndex = 0;

      Future<void> encryptPending() async {
        final clear = pending.takeBytes();
        if (clear.isEmpty) return;
        final box = await _algorithm.encrypt(
          clear,
          secretKey: key,
          nonce: _chunkNonce(baseNonce, chunkIndex),
          aad: _chunkAad(accountId, clientMessageId, token, chunkIndex),
        );
        sink
          ..add(box.cipherText)
          ..add(box.mac.bytes);
        chunkIndex++;
      }

      await for (final chunk in source) {
        if (chunk.isEmpty) continue;
        observedLength += chunk.length;
        if (observedLength > clearLength) {
          throw StateError('Selected file changed while it was being copied.');
        }
        digestInput.add(chunk);
        var offset = 0;
        while (offset < chunk.length) {
          final take = min(
            _clearChunkSize - pending.length,
            chunk.length - offset,
          );
          pending.add(chunk.sublist(offset, offset + take));
          offset += take;
          if (pending.length == _clearChunkSize) await encryptPending();
        }
      }
      digestInput.close();
      digestClosed = true;
      if (observedLength != clearLength) {
        throw StateError('Selected file changed while it was being copied.');
      }
      await encryptPending();
      final completedDigest = digest;
      if (completedDigest == null) {
        throw StateError('Outbox file hashing did not complete.');
      }
      await sink.flush();
      await sink.close();
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      return ImOutboxStoredFile(
        token: token,
        role: role,
        fileName: fileName,
        contentType: contentType,
        length: clearLength,
        sha256: completedDigest.toString(),
        width: width,
        height: height,
      );
    } catch (_) {
      if (!digestClosed) {
        try {
          digestInput.close();
        } catch (_) {
          // Preserve the original copy/encryption failure.
        }
      }
      try {
        await sink.close();
      } catch (_) {
        // addStream may already have closed the sink after a source error.
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Stream<List<int>> openRead({
    required String accountId,
    required String clientMessageId,
    required ImOutboxStoredFile file,
  }) async* {
    final source = await _file(accountId, file.token, create: false);
    final metadata = await _readHeader(source);
    if (metadata.clearLength != file.length) {
      throw StateError('Queued media length does not match its metadata.');
    }
    var yielded = 0;
    if (metadata.version == 1) {
      final mac = metadata.mac;
      if (mac == null) throw StateError('Queued media file is malformed.');
      await for (final chunk in _algorithm.decryptStream(
        source.openRead(_v1HeaderLength, metadata.cipherEnd),
        secretKey: await _key(accountId),
        nonce: metadata.nonce,
        mac: mac,
        aad: _aadV1(accountId, clientMessageId, file.token),
      )) {
        yielded += chunk.length;
        yield chunk;
      }
    } else {
      final reader = await source.open(mode: FileMode.read);
      try {
        await reader.setPosition(_v2HeaderLength);
        final key = await _key(accountId);
        final macLength = _algorithm.macAlgorithm.macLength;
        var remaining = metadata.clearLength;
        var chunkIndex = 0;
        while (remaining > 0) {
          final clearChunkLength = min(metadata.chunkSize, remaining);
          final cipherText = await reader.read(clearChunkLength);
          final macBytes = await reader.read(macLength);
          if (cipherText.length != clearChunkLength ||
              macBytes.length != macLength) {
            throw StateError('Queued media payload is incomplete.');
          }
          final clear = await _algorithm.decrypt(
            SecretBox(
              cipherText,
              nonce: _chunkNonce(metadata.nonce, chunkIndex),
              mac: Mac(macBytes),
            ),
            secretKey: key,
            aad: _chunkAad(accountId, clientMessageId, file.token, chunkIndex),
          );
          if (clear.length != clearChunkLength) {
            throw StateError('Queued media payload is incomplete.');
          }
          yielded += clear.length;
          remaining -= clear.length;
          chunkIndex++;
          yield clear;
        }
      } finally {
        await reader.close();
      }
    }
    if (yielded != file.length) {
      throw StateError('Queued media payload is incomplete.');
    }
  }

  Future<void> verify({
    required String accountId,
    required String clientMessageId,
    required ImOutboxStoredFile file,
  }) async {
    final digest = await crypto.sha256
        .bind(
          openRead(
            accountId: accountId,
            clientMessageId: clientMessageId,
            file: file,
          ),
        )
        .first;
    if (digest.toString() != file.sha256) {
      throw StateError('Queued media digest does not match its metadata.');
    }
  }

  Future<Uint8List> readBytes({
    required String accountId,
    required String clientMessageId,
    required ImOutboxStoredFile file,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in openRead(
      accountId: accountId,
      clientMessageId: clientMessageId,
      file: file,
    )) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (crypto.sha256.convert(bytes).toString() != file.sha256) {
      throw StateError('Queued media digest does not match its metadata.');
    }
    return bytes;
  }

  Future<void> deleteAll(
    String accountId,
    Iterable<ImOutboxStoredFile> files,
  ) async {
    for (final item in files) {
      try {
        final file = await _file(accountId, item.token, create: false);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The database is authoritative. Orphan cleanup is best effort.
      }
    }
  }

  /// Removes incomplete encrypted containers left when the process is killed
  /// between opening the temporary file and its final atomic rename.
  ///
  /// Call once for the active account before starting normal file operations;
  /// completed `.imq` containers are never touched.
  Future<void> deleteIncompleteWrites(String accountId) async {
    try {
      final directory = await _accountDirectory(accountId, create: false);
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.imq.tmp')) continue;
        await entity.delete();
      }
    } catch (_) {
      // Startup cleanup is best effort. A later start retries the same file.
    }
  }

  Future<File> _file(
    String accountId,
    String token, {
    bool create = true,
  }) async {
    if (token.trim().isEmpty) throw StateError('Queued media token is empty.');
    final accountDirectory = await _accountDirectory(accountId, create: create);
    final name = crypto.sha256.convert(utf8.encode(token)).toString();
    return File(path.join(accountDirectory.path, '$name.imq'));
  }

  Future<Directory> _accountDirectory(
    String accountId, {
    required bool create,
  }) async {
    final root = await _directoryLoader();
    final directory = Directory(
      path.join(
        root.path,
        AppEnvironment.storageNamespace,
        crypto.sha256.convert(utf8.encode(accountId)).toString(),
      ),
    );
    if (create) await directory.create(recursive: true);
    return directory;
  }

  Future<
    ({
      int version,
      int clearLength,
      int chunkSize,
      List<int> nonce,
      Mac? mac,
      int cipherEnd,
    })
  >
  _readHeader(File file) async {
    if (!await file.exists()) throw StateError('Queued media file is missing.');
    final length = await file.length();
    if (length < _v1HeaderLength + _algorithm.macAlgorithm.macLength) {
      throw StateError('Queued media file is malformed.');
    }
    final reader = await file.open(mode: FileMode.read);
    try {
      final magic = await reader.read(_magicV1.length);
      final version = _bytesEqual(magic, _magicV1)
          ? 1
          : _bytesEqual(magic, _magicV2)
          ? 2
          : 0;
      if (version == 0) {
        throw StateError('Queued media file has an unsupported format.');
      }
      final clearLengthBytes = await reader.read(_lengthBytes);
      if (clearLengthBytes.length != _lengthBytes) {
        throw StateError('Queued media file is malformed.');
      }
      final clearLength = ByteData.sublistView(
        Uint8List.fromList(clearLengthBytes),
      ).getUint64(0, Endian.big);
      if (clearLength <= 0) {
        throw StateError('Queued media file is malformed.');
      }
      final macLength = _algorithm.macAlgorithm.macLength;
      if (version == 1) {
        final nonce = await reader.read(_algorithm.nonceLength);
        if (nonce.length != _algorithm.nonceLength ||
            length != _v1HeaderLength + clearLength + macLength) {
          throw StateError('Queued media file is malformed.');
        }
        await reader.setPosition(length - macLength);
        final macBytes = await reader.read(macLength);
        if (macBytes.length != macLength) {
          throw StateError('Queued media file is malformed.');
        }
        return (
          version: 1,
          clearLength: clearLength,
          chunkSize: clearLength,
          nonce: nonce,
          mac: Mac(macBytes),
          cipherEnd: length - macLength,
        );
      }

      final chunkSizeBytes = await reader.read(_chunkSizeBytes);
      final nonce = await reader.read(_algorithm.nonceLength);
      if (chunkSizeBytes.length != _chunkSizeBytes ||
          nonce.length != _algorithm.nonceLength) {
        throw StateError('Queued media file is malformed.');
      }
      final chunkSize = ByteData.sublistView(Uint8List.fromList(chunkSizeBytes))
          .getUint32(0, Endian.big);
      if (chunkSize <= 0 || chunkSize > 4 * 1024 * 1024) {
        throw StateError('Queued media file is malformed.');
      }
      final chunkCount = (clearLength + chunkSize - 1) ~/ chunkSize;
      final expectedLength =
          _v2HeaderLength + clearLength + chunkCount * macLength;
      if (length != expectedLength) {
        throw StateError('Queued media file is malformed.');
      }
      return (
        version: 2,
        clearLength: clearLength,
        chunkSize: chunkSize,
        nonce: nonce,
        mac: null,
        cipherEnd: length,
      );
    } finally {
      await reader.close();
    }
  }

  Uint8List _v2Header(int clearLength, List<int> nonce) {
    final header = Uint8List(_v2HeaderLength);
    header.setRange(0, _magicV2.length, _magicV2);
    ByteData.sublistView(header)
      ..setUint64(_magicV2.length, clearLength, Endian.big)
      ..setUint32(_magicV2.length + _lengthBytes, _clearChunkSize, Endian.big);
    header.setRange(
      _magicV2.length + _lengthBytes + _chunkSizeBytes,
      _v2HeaderLength,
      nonce,
    );
    return header;
  }

  List<int> _aadV1(String accountId, String clientMessageId, String token) =>
      utf8.encode('im-outbox-file-v1|$accountId|$clientMessageId|$token');

  List<int> _chunkAad(
    String accountId,
    String clientMessageId,
    String token,
    int chunkIndex,
  ) => utf8.encode(
    'im-outbox-file-v2|$accountId|$clientMessageId|$token|$chunkIndex',
  );

  List<int> _chunkNonce(List<int> baseNonce, int chunkIndex) {
    final nonce = Uint8List.fromList(baseNonce);
    final data = ByteData.sublistView(nonce);
    final offset = nonce.length - 8;
    final base = data.getUint64(offset, Endian.big);
    data.setUint64(
      offset,
      (base + chunkIndex) & 0xFFFFFFFFFFFFFFFF,
      Endian.big,
    );
    return nonce;
  }

  Future<SecretKey> _key(String accountId) =>
      _keys.putIfAbsent(accountId, () async {
        final bytes = await _keyLoader(accountId);
        if (bytes.length != 32) {
          throw StateError('IM cache key must contain 32 bytes.');
        }
        return SecretKey(bytes);
      });

  static String _newToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static Future<Directory> _defaultDirectory() async => Directory(
    path.join((await getApplicationSupportDirectory()).path, 'im-outbox-files'),
  );
}

int _outboxInteger(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

int? _outboxNullableInteger(Object? value) {
  if (value == null) return null;
  final parsed = _outboxInteger(value);
  return parsed == 0 && value.toString() != '0' ? null : parsed;
}

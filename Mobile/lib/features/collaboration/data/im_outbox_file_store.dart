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
/// clear bytes never appear in paths. The file format is:
/// `magic | clear length | nonce | cipher text | MAC`.
final class ImOutboxFileStore {
  ImOutboxFileStore({
    required this._keyLoader,
    ImOutboxDirectoryLoader? directoryLoader,
  }) : _directoryLoader = directoryLoader ?? _defaultDirectory;

  static final Uint8List _magic = Uint8List.fromList(ascii.encode('IMOBX001'));
  static const int _lengthBytes = 8;

  final Future<List<int>> Function(String accountId) _keyLoader;
  final ImOutboxDirectoryLoader _directoryLoader;
  final Cipher _algorithm = AesGcm.with256bits();
  final Map<String, Future<SecretKey>> _keys = {};

  int get _headerLength =>
      _magic.length + _lengthBytes + _algorithm.nonceLength;

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
    final nonce = _algorithm.newNonce();
    final sink = temporary.openWrite();
    crypto.Digest? digest;
    final digestOutput = ChunkedConversionSink<crypto.Digest>.withCallback(
      (values) => digest = values.single,
    );
    final digestInput = crypto.sha256.startChunkedConversion(digestOutput);
    var digestClosed = false;
    var observedLength = 0;

    Stream<List<int>> observedSource() async* {
      await for (final chunk in source) {
        if (chunk.isEmpty) continue;
        observedLength += chunk.length;
        if (observedLength > clearLength) {
          throw StateError('Selected file changed while it was being copied.');
        }
        digestInput.add(chunk);
        yield chunk;
      }
      digestInput.close();
      digestClosed = true;
      if (observedLength != clearLength) {
        throw StateError('Selected file changed while it was being copied.');
      }
    }

    Mac? mac;
    try {
      sink.add(_header(clearLength, nonce));
      await sink.addStream(
        _algorithm.encryptStream(
          observedSource(),
          secretKey: await _key(accountId),
          nonce: nonce,
          aad: _aad(accountId, clientMessageId, token),
          onMac: (value) => mac = value,
        ),
      );
      final completedMac = mac;
      if (completedMac == null) {
        throw StateError('Outbox file encryption did not produce a MAC.');
      }
      final completedDigest = digest;
      if (completedDigest == null) {
        throw StateError('Outbox file hashing did not complete.');
      }
      sink.add(completedMac.bytes);
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
    await for (final chunk in _algorithm.decryptStream(
      source.openRead(_headerLength, metadata.cipherEnd),
      secretKey: await _key(accountId),
      nonce: metadata.nonce,
      mac: metadata.mac,
      aad: _aad(accountId, clientMessageId, file.token),
    )) {
      yielded += chunk.length;
      yield chunk;
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

  Future<File> _file(
    String accountId,
    String token, {
    bool create = true,
  }) async {
    if (token.trim().isEmpty) throw StateError('Queued media token is empty.');
    final root = await _directoryLoader();
    final accountDirectory = Directory(
      path.join(
        root.path,
        AppEnvironment.storageNamespace,
        crypto.sha256.convert(utf8.encode(accountId)).toString(),
      ),
    );
    if (create) await accountDirectory.create(recursive: true);
    final name = crypto.sha256.convert(utf8.encode(token)).toString();
    return File(path.join(accountDirectory.path, '$name.imq'));
  }

  Future<({int clearLength, List<int> nonce, Mac mac, int cipherEnd})>
  _readHeader(File file) async {
    if (!await file.exists()) throw StateError('Queued media file is missing.');
    final length = await file.length();
    final minimumLength = _headerLength + _algorithm.macAlgorithm.macLength;
    if (length < minimumLength) {
      throw StateError('Queued media file is malformed.');
    }
    final reader = await file.open(mode: FileMode.read);
    try {
      final magic = await reader.read(_magic.length);
      if (!_bytesEqual(magic, _magic)) {
        throw StateError('Queued media file has an unsupported format.');
      }
      final clearLengthBytes = await reader.read(_lengthBytes);
      final clearLength = ByteData.sublistView(
        Uint8List.fromList(clearLengthBytes),
      ).getUint64(0, Endian.big);
      final nonce = await reader.read(_algorithm.nonceLength);
      final macLength = _algorithm.macAlgorithm.macLength;
      await reader.setPosition(length - macLength);
      final mac = Mac(await reader.read(macLength));
      return (
        clearLength: clearLength,
        nonce: nonce,
        mac: mac,
        cipherEnd: length - macLength,
      );
    } finally {
      await reader.close();
    }
  }

  Uint8List _header(int clearLength, List<int> nonce) {
    final header = Uint8List(_headerLength);
    header.setRange(0, _magic.length, _magic);
    ByteData.sublistView(header)
        .setUint64(_magic.length, clearLength, Endian.big);
    header.setRange(_magic.length + _lengthBytes, _headerLength, nonce);
    return header;
  }

  List<int> _aad(String accountId, String clientMessageId, String token) =>
      utf8.encode('im-outbox-file-v1|$accountId|$clientMessageId|$token');

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

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef ImMessageImageCacheDirectoryLoader = Future<Directory> Function();

final class ImMessageImageDiskCache {
  ImMessageImageDiskCache({
    ImMessageImageCacheDirectoryLoader? directoryLoader,
    this.maxFiles = 160,
    this.maxBytes = 96 * 1024 * 1024,
  }) : _directoryLoader = directoryLoader ?? _defaultDirectory;

  final ImMessageImageCacheDirectoryLoader _directoryLoader;
  final int maxFiles;
  final int maxBytes;

  Future<Uint8List?> read({
    required String accountId,
    required String imageId,
    required String sha256Value,
  }) async {
    if (accountId.trim().isEmpty || imageId.trim().isEmpty) return null;
    try {
      final file = await _cacheFile(
        accountId: accountId,
        imageId: imageId,
        sha256Value: sha256Value,
      );
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || !_matchesDigest(bytes, sha256Value)) {
        await file.delete();
        return null;
      }
      await file.setLastModified(DateTime.now());
      return bytes;
    } catch (_) {
      // Disk caching is an optimization and must never block message display.
      return null;
    }
  }

  Future<void> write({
    required String accountId,
    required String imageId,
    required String sha256Value,
    required Uint8List bytes,
  }) async {
    if (accountId.trim().isEmpty ||
        imageId.trim().isEmpty ||
        bytes.isEmpty ||
        bytes.lengthInBytes > maxBytes ||
        !_matchesDigest(bytes, sha256Value)) {
      return;
    }
    File? temporary;
    try {
      final target = await _cacheFile(
        accountId: accountId,
        imageId: imageId,
        sha256Value: sha256Value,
      );
      if (await target.exists()) {
        await target.setLastModified(DateTime.now());
        return;
      }
      temporary = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temporary.writeAsBytes(bytes, flush: true);
      if (await target.exists()) {
        await temporary.delete();
      } else {
        await temporary.rename(target.path);
      }
      await _trim(target.parent);
    } catch (_) {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<File> _cacheFile({
    required String accountId,
    required String imageId,
    required String sha256Value,
  }) async {
    final directory = await _directoryLoader();
    await directory.create(recursive: true);
    final normalizedDigest = sha256Value.trim().toLowerCase();
    final identity = _isSha256(normalizedDigest)
        ? normalizedDigest
        : imageId.trim();
    final fileName = crypto.sha256
        .convert('$accountId|$identity'.codeUnits)
        .toString();
    return File(path.join(directory.path, '$fileName.bin'));
  }

  Future<void> _trim(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.bin'))
        .cast<File>()
        .toList();
    final entries = <({File file, DateTime modified, int size})>[];
    var totalBytes = 0;
    for (final file in files) {
      final stat = await file.stat();
      totalBytes += stat.size;
      entries.add((file: file, modified: stat.modified, size: stat.size));
    }
    if (entries.length <= maxFiles && totalBytes <= maxBytes) return;
    entries.sort((left, right) => left.modified.compareTo(right.modified));
    var remainingFiles = entries.length;
    for (final entry in entries) {
      if (remainingFiles <= maxFiles && totalBytes <= maxBytes) break;
      await entry.file.delete();
      remainingFiles -= 1;
      totalBytes -= entry.size;
    }
  }

  static bool _matchesDigest(Uint8List bytes, String sha256Value) {
    final normalized = sha256Value.trim().toLowerCase();
    return !_isSha256(normalized) ||
        crypto.sha256.convert(bytes).toString() == normalized;
  }

  static bool _isSha256(String value) =>
      value.length == 64 && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  static Future<Directory> _defaultDirectory() async => Directory(
    path.join(
      (await getApplicationSupportDirectory()).path,
      'im-message-images',
    ),
  );
}

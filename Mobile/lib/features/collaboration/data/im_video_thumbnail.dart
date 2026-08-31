import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail_gdx_plus/video_thumbnail_gdx_plus.dart';

final class ImVideoThumbnail {
  const ImVideoThumbnail({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

String imVideoPreviewCacheKey({
  required String attachmentId,
  required String sha256Value,
  required String coverObjectId,
}) {
  if (coverObjectId.trim().isNotEmpty) return 'cover:${coverObjectId.trim()}';
  if (sha256Value.trim().isNotEmpty) return 'video:${sha256Value.trim()}';
  return 'attachment:${attachmentId.trim()}';
}

Future<String?> readImVideoPreviewCachePath(String cacheKey) async {
  try {
    final file = await _previewCacheFile(cacheKey);
    if (!await file.exists()) return null;
    if (await file.length() == 0) {
      await file.delete();
      return null;
    }
    return file.path;
  } catch (_) {
    return null;
  }
}

Future<String?> writeImVideoPreviewCache(
  String cacheKey,
  Uint8List bytes,
) async {
  if (bytes.isEmpty) return null;
  try {
    final target = await _previewCacheFile(cacheKey);
    if (await target.exists()) return target.path;
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
    await _trimPreviewCache(target.parent);
    return target.path;
  } catch (_) {
    // Preview caching is an optimization and must never block message delivery.
    return null;
  }
}

Future<File> _previewCacheFile(String cacheKey) async {
  final directory = Directory(
    path.join(
      (await getApplicationSupportDirectory()).path,
      'im-video-previews',
    ),
  );
  await directory.create(recursive: true);
  final digest = sha256.convert(cacheKey.codeUnits).toString();
  return File(path.join(directory.path, '$digest.jpg'));
}

Future<void> _trimPreviewCache(Directory directory) async {
  const maxFiles = 160;
  const maxBytes = 96 * 1024 * 1024;
  final files = await directory
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.jpg'))
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

Future<ImVideoThumbnail?> createImVideoThumbnail({
  required Uint8List videoBytes,
  required String fileName,
}) async {
  if (videoBytes.isEmpty) return null;
  final directory = await getTemporaryDirectory();
  final sourceExtension = path.extension(fileName).toLowerCase();
  final extension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(sourceExtension)
      ? sourceExtension
      : '.mp4';
  final source = File(
    path.join(
      directory.path,
      'im-video-${DateTime.now().microsecondsSinceEpoch}$extension',
    ),
  );
  try {
    await source.writeAsBytes(videoBytes, flush: true);
    final bytes = await VideoThumbnail.thumbnailData(
      video: source.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 960,
      timeMs: 0,
      quality: 86,
    );
    if (bytes == null || bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        return ImVideoThumbnail(
          bytes: bytes,
          width: frame.image.width,
          height: frame.image.height,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  } finally {
    if (await source.exists()) await source.delete();
  }
}

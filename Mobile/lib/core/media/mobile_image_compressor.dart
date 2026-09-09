import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'mobile_upload_policy.dart';

enum MobileImagePurpose { avatar, avatarCrop, message, approval }

final class MobilePreparedImage {
  const MobilePreparedImage({
    required this.fileName,
    required this.bytes,
    required this.contentType,
    required this.compressed,
  });

  final String fileName;
  final Uint8List bytes;
  final String contentType;
  final bool compressed;
}

typedef MobileImageEncoder = Future<Uint8List> Function(
  Uint8List source, {
  required int maxDimension,
  required int quality,
  required bool webp,
});

final mobileImageCompressorProvider = Provider<MobileImageCompressor>(
  (ref) => MobileImageCompressor(),
);

typedef MobileImageFileEncoder = Future<Uint8List> Function(
  String sourcePath, {
  required int maxDimension,
  required int quality,
  required bool webp,
});

typedef MobileTemporaryDirectoryLoader = Future<Directory> Function();
typedef MobileFileModifiedAtLoader = Future<DateTime> Function(
  FileSystemEntity entity,
);

const _mobileImageSourcePrefix = 'mobile-image-source-';
final _activeMobileImageSourcePaths = <String>{};

/// Removes private image sources left behind when the OS terminates the app
/// before [prepareStream] reaches its `finally` block. This deliberately only
/// touches directories created by this module; unrelated cache entries and
/// files with a similar name are preserved.
Future<void> deleteIncompleteMobileImageSources({
  MobileTemporaryDirectoryLoader temporaryDirectoryLoader =
      getTemporaryDirectory,
  DateTime? createdBefore,
  MobileFileModifiedAtLoader modifiedAtLoader = _modifiedAt,
}) async {
  try {
    final cache = await temporaryDirectoryLoader();
    await for (final entity in cache.list(followLinks: false)) {
      if (entity is! Directory ||
          !path.basename(entity.path).startsWith(_mobileImageSourcePrefix)) {
        continue;
      }
      try {
        if (_activeMobileImageSourcePaths.contains(entity.path)) continue;
        if (createdBefore != null) {
          final modifiedAt = await modifiedAtLoader(entity);
          if (modifiedAt.isAfter(createdBefore)) continue;
        }
        if (_activeMobileImageSourcePaths.contains(entity.path)) continue;
        await entity.delete(recursive: true);
      } catch (_) {
        // A locked or concurrently removed cache entry must not block startup.
      }
    }
  } catch (_) {
    // Cache discovery is best effort and must never block app startup.
  }
}

Future<DateTime> _modifiedAt(FileSystemEntity entity) async =>
    (await entity.stat()).modified;

final class MobileImageCompressor {
  MobileImageCompressor({
    MobileImageEncoder? encoder,
    MobileImageFileEncoder? fileEncoder,
    MobileTemporaryDirectoryLoader? temporaryDirectoryLoader,
  }) : _encoder = encoder ?? _compressJpeg,
       _fileEncoder = fileEncoder ?? _compressJpegFile,
       _temporaryDirectoryLoader =
           temporaryDirectoryLoader ?? getTemporaryDirectory;

  final MobileImageEncoder _encoder;
  final MobileImageFileEncoder _fileEncoder;
  final MobileTemporaryDirectoryLoader _temporaryDirectoryLoader;

  Future<MobilePreparedImage> prepare({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required MobileImagePurpose purpose,
  }) async {
    final normalizedType = contentType.trim().toLowerCase();
    if (bytes.isEmpty ||
        !isMobileLocallyCompressibleImageType(normalizedType) ||
        bytes.length <= _triggerBytes(purpose)) {
      return MobilePreparedImage(
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
        compressed: false,
      );
    }

    var best = bytes;
    var encodedAtLeastOnce = false;
    for (final attempt in _attempts(purpose)) {
      late final Uint8List encoded;
      try {
        encoded = await _encoder(
          bytes,
          maxDimension: attempt.dimension,
          quality: attempt.quality,
          webp: purpose == MobileImagePurpose.avatar,
        );
        encodedAtLeastOnce = true;
      } catch (_) {
        // A lower resolution/quality attempt may still succeed after a native
        // decoder allocation or format-specific failure.
        continue;
      }
      if (encoded.isNotEmpty && encoded.length < best.length) best = encoded;
      if (best.length <= _targetBytes(purpose)) break;
    }
    if (!encodedAtLeastOnce) {
      throw const MobileUploadProcessingException('图片处理失败，请重新选择或换一张图片');
    }
    if (identical(best, bytes)) {
      return MobilePreparedImage(
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
        compressed: false,
      );
    }
    return MobilePreparedImage(
      fileName:
          '${path.basenameWithoutExtension(fileName)}.${purpose == MobileImagePurpose.avatar ? 'webp' : 'jpg'}',
      bytes: best,
      contentType: purpose == MobileImagePurpose.avatar
          ? 'image/webp'
          : 'image/jpeg',
      compressed: true,
    );
  }

  /// Prepares a picker-backed image without retaining the original large image
  /// in the Dart heap. The temporary source lives only in the app-private cache
  /// and is removed in [finally], including encoder failures.
  Future<MobilePreparedImage> prepareStream({
    required String fileName,
    required int sourceLength,
    required Stream<List<int>> Function() openRead,
    required String contentType,
    required MobileImagePurpose purpose,
  }) async {
    final normalizedType = contentType.trim().toLowerCase();
    if (sourceLength <= _triggerBytes(purpose) ||
        !isMobileLocallyCompressibleImageType(normalizedType)) {
      final bytes = await _readStream(openRead);
      return prepare(
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
        purpose: purpose,
      );
    }

    Directory? workingDirectory;
    try {
      final cache = await _temporaryDirectoryLoader();
      workingDirectory = await cache.createTemp(_mobileImageSourcePrefix);
      _activeMobileImageSourcePaths.add(workingDirectory.path);
      final source = File(
        path.join(workingDirectory.path, 'source${path.extension(fileName)}'),
      );
      final sink = source.openWrite();
      try {
        await sink.addStream(openRead());
      } finally {
        await sink.close();
      }
      final actualLength = await source.length();
      if (actualLength <= 0 ||
          (sourceLength > 0 && actualLength != sourceLength)) {
        throw const FileSystemException('Image source could not be read');
      }

      Uint8List? best;
      var encodedAtLeastOnce = false;
      for (final attempt in _attempts(purpose)) {
        late final Uint8List encoded;
        try {
          encoded = await _fileEncoder(
            source.path,
            maxDimension: attempt.dimension,
            quality: attempt.quality,
            webp: purpose == MobileImagePurpose.avatar,
          );
          encodedAtLeastOnce = true;
        } catch (_) {
          continue;
        }
        if (encoded.isNotEmpty &&
            (purpose == MobileImagePurpose.avatarCrop ||
                encoded.length < (best?.length ?? actualLength))) {
          best = encoded;
        }
        if (best != null && best.length <= _targetBytes(purpose)) break;
      }
      if (!encodedAtLeastOnce) {
        throw const MobileUploadProcessingException('图片处理失败，请重新选择或换一张图片');
      }
      if (best == null) {
        return MobilePreparedImage(
          fileName: fileName,
          bytes: await source.readAsBytes(),
          contentType: contentType,
          compressed: false,
        );
      }
      return MobilePreparedImage(
        fileName:
            '${path.basenameWithoutExtension(fileName)}.${purpose == MobileImagePurpose.avatar ? 'webp' : 'jpg'}',
        bytes: best,
        contentType: purpose == MobileImagePurpose.avatar
            ? 'image/webp'
            : 'image/jpeg',
        compressed: true,
      );
    } finally {
      if (workingDirectory != null) {
        _activeMobileImageSourcePaths.remove(workingDirectory.path);
        try {
          await workingDirectory.delete(recursive: true);
        } on FileSystemException {
          // Best-effort cache cleanup. A later OS cache sweep may remove it.
        }
      }
    }
  }
}

Future<Uint8List> _readStream(Stream<List<int>> Function() openRead) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in openRead()) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

String mobileImageContentType(String fileName) =>
    switch (path.extension(fileName).replaceFirst('.', '').toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' || 'heif' => 'image/heic',
      _ => 'application/octet-stream',
    };

int _triggerBytes(MobileImagePurpose purpose) => switch (purpose) {
  // Desktop always produces a 256 px WebP thumbnail. Mobile does the same
  // instead of relying on the original file size or Base64 expansion.
  MobileImagePurpose.avatar || MobileImagePurpose.avatarCrop => 0,
  MobileImagePurpose.message || MobileImagePurpose.approval => 2 * 1024 * 1024,
};

int _targetBytes(MobileImagePurpose purpose) => switch (purpose) {
  MobileImagePurpose.avatar => 120 * 1024,
  MobileImagePurpose.avatarCrop => 2 * 1024 * 1024,
  MobileImagePurpose.message || MobileImagePurpose.approval => 3 * 1024 * 1024,
};

List<({int dimension, int quality})> _attempts(MobileImagePurpose purpose) =>
    switch (purpose) {
      MobileImagePurpose.avatar => const [
        (dimension: 256, quality: 90),
        (dimension: 256, quality: 82),
        (dimension: 256, quality: 74),
        (dimension: 256, quality: 66),
      ],
      MobileImagePurpose.avatarCrop => const [
        (dimension: 1600, quality: 92),
        (dimension: 1280, quality: 88),
      ],
      MobileImagePurpose.message || MobileImagePurpose.approval => const [
        (dimension: 2560, quality: 86),
        (dimension: 2048, quality: 78),
        (dimension: 1600, quality: 70),
        (dimension: 1280, quality: 62),
      ],
    };

Future<Uint8List> _compressJpeg(
  Uint8List source, {
  required int maxDimension,
  required int quality,
  required bool webp,
}) => FlutterImageCompress.compressWithList(
  source,
  minWidth: maxDimension,
  minHeight: maxDimension,
  quality: quality,
  format: webp ? CompressFormat.webp : CompressFormat.jpeg,
  keepExif: false,
  autoCorrectionAngle: true,
);

Future<Uint8List> _compressJpegFile(
  String sourcePath, {
  required int maxDimension,
  required int quality,
  required bool webp,
}) async {
  final dimensions = await _readRasterDimensions(File(sourcePath));
  final geometry = dimensions == null
      ? (width: maxDimension, height: maxDimension, sampleSize: 1)
      : mobileImageSampledGeometry(
          width: dimensions.width,
          height: dimensions.height,
          maxDimension: maxDimension,
        );
  return await FlutterImageCompress.compressWithFile(
        sourcePath,
        minWidth: geometry.width,
        minHeight: geometry.height,
        inSampleSize: geometry.sampleSize,
        quality: quality,
        format: webp ? CompressFormat.webp : CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      ) ??
      Uint8List(0);
}

({int width, int height, int sampleSize}) mobileImageSampledGeometry({
  required int width,
  required int height,
  required int maxDimension,
}) {
  if (width <= 0 || height <= 0 || maxDimension <= 0) {
    return (width: maxDimension, height: maxDimension, sampleSize: 1);
  }
  final sourceMax = width > height ? width : height;
  final scale = sourceMax > maxDimension ? maxDimension / sourceMax : 1.0;
  final targetWidth = (width * scale).round().clamp(1, width);
  final targetHeight = (height * scale).round().clamp(1, height);
  var sampleSize = 1;
  while (sourceMax ~/ (sampleSize * 2) >= maxDimension) {
    sampleSize *= 2;
  }
  return (width: targetWidth, height: targetHeight, sampleSize: sampleSize);
}

Future<({int width, int height})?> _readRasterDimensions(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final length = await handle.length();
    final bytes = await handle.read(length.clamp(0, 1024 * 1024));
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      final width = _uint32(bytes, 16);
      final height = _uint32(bytes, 20);
      return width > 0 && height > 0 ? (width: width, height: height) : null;
    }
    if (bytes.length < 10 || bytes[0] != 0xff || bytes[1] != 0xd8) {
      return null;
    }
    var offset = 2;
    while (offset + 9 < bytes.length) {
      while (offset < bytes.length && bytes[offset] != 0xff) {
        offset++;
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 0xd8 || marker == 0xd9 || marker == 0x01) continue;
      if (offset + 1 >= bytes.length) break;
      final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
      if (segmentLength < 2 || offset + segmentLength > bytes.length) break;
      if (_jpegStartOfFrameMarkers.contains(marker) && segmentLength >= 7) {
        final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
        final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        return width > 0 && height > 0 ? (width: width, height: height) : null;
      }
      offset += segmentLength;
    }
  } catch (_) {
    return null;
  } finally {
    await handle?.close();
  }
  return null;
}

int _uint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

const _jpegStartOfFrameMarkers = {
  0xc0,
  0xc1,
  0xc2,
  0xc3,
  0xc5,
  0xc6,
  0xc7,
  0xc9,
  0xca,
  0xcb,
  0xcd,
  0xce,
  0xcf,
};

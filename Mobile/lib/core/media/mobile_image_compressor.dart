import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

enum MobileImagePurpose { avatar, message, approval }

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

final class MobileImageCompressor {
  MobileImageCompressor({MobileImageEncoder? encoder})
    : _encoder = encoder ?? _compressJpeg;

  final MobileImageEncoder _encoder;

  Future<MobilePreparedImage> prepare({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    required MobileImagePurpose purpose,
  }) async {
    final normalizedType = contentType.trim().toLowerCase();
    if (bytes.isEmpty ||
        !_compressibleContentTypes.contains(normalizedType) ||
        bytes.length <= _triggerBytes(purpose)) {
      return MobilePreparedImage(
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
        compressed: false,
      );
    }

    var best = bytes;
    for (final attempt in _attempts(purpose)) {
      final encoded = await _encoder(
        bytes,
        maxDimension: attempt.dimension,
        quality: attempt.quality,
        webp: purpose == MobileImagePurpose.avatar,
      );
      if (encoded.isNotEmpty && encoded.length < best.length) best = encoded;
      if (best.length <= _targetBytes(purpose)) break;
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
  MobileImagePurpose.avatar => 0,
  MobileImagePurpose.message || MobileImagePurpose.approval => 2 * 1024 * 1024,
};

int _targetBytes(MobileImagePurpose purpose) => switch (purpose) {
  MobileImagePurpose.avatar => 120 * 1024,
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
      MobileImagePurpose.message || MobileImagePurpose.approval => const [
        (dimension: 2560, quality: 86),
        (dimension: 2048, quality: 78),
        (dimension: 1600, quality: 70),
        (dimension: 1280, quality: 62),
      ],
    };

const _compressibleContentTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/heic',
  'image/heif',
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

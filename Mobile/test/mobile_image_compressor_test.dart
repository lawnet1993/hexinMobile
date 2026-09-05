import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/media/mobile_image_compressor.dart';

void main() {
  test(
    'small image is preserved without invoking native compression',
    () async {
      var calls = 0;
      final compressor = MobileImageCompressor(
        encoder:
            (
              source, {
              required maxDimension,
              required quality,
              required webp,
            }) async {
              calls++;
              return source;
            },
      );
      final source = Uint8List(1024);

      final result = await compressor.prepare(
        fileName: 'receipt.png',
        bytes: source,
        contentType: 'image/png',
        purpose: MobileImagePurpose.approval,
      );

      expect(result.bytes, same(source));
      expect(result.fileName, 'receipt.png');
      expect(result.contentType, 'image/png');
      expect(result.compressed, isFalse);
      expect(calls, 0);
    },
  );

  test(
    'large phone photo is compressed and converted to jpeg metadata',
    () async {
      var calls = 0;
      final compressor = MobileImageCompressor(
        encoder:
            (
              source, {
              required maxDimension,
              required quality,
              required webp,
            }) async {
              calls++;
              return Uint8List(2 * 1024 * 1024);
            },
      );

      final result = await compressor.prepare(
        fileName: 'IMG_001.heic',
        bytes: Uint8List(12 * 1024 * 1024),
        contentType: 'image/heic',
        purpose: MobileImagePurpose.message,
      );

      expect(calls, 1);
      expect(result.bytes.length, 2 * 1024 * 1024);
      expect(result.fileName, 'IMG_001.jpg');
      expect(result.contentType, 'image/jpeg');
      expect(result.compressed, isTrue);
    },
  );

  test('documents are never modified by the image compressor', () async {
    var calls = 0;
    final compressor = MobileImageCompressor(
      encoder:
          (
            source, {
            required maxDimension,
            required quality,
            required webp,
          }) async {
            calls++;
            return Uint8List(1);
          },
    );
    final source = Uint8List(24 * 1024 * 1024);

    final result = await compressor.prepare(
      fileName: 'contract.pdf',
      bytes: source,
      contentType: 'application/pdf',
      purpose: MobileImagePurpose.approval,
    );

    expect(result.bytes, same(source));
    expect(result.fileName, 'contract.pdf');
    expect(result.contentType, 'application/pdf');
    expect(result.compressed, isFalse);
    expect(calls, 0);
  });

  test('a 200 KB avatar is resized instead of rejected', () async {
    var calls = 0;
    final compressor = MobileImageCompressor(
      encoder:
          (
            source, {
            required maxDimension,
            required quality,
            required webp,
          }) async {
            calls++;
            expect(maxDimension, 256);
            expect(webp, isTrue);
            return Uint8List(72 * 1024);
          },
    );

    final result = await compressor.prepare(
      fileName: 'portrait.jpg',
      bytes: Uint8List(200 * 1024),
      contentType: 'image/jpeg',
      purpose: MobileImagePurpose.avatar,
    );

    expect(calls, 1);
    expect(result.bytes.length, 72 * 1024);
    expect(result.fileName, 'portrait.webp');
    expect(result.contentType, 'image/webp');
    expect(result.compressed, isTrue);
  });
}

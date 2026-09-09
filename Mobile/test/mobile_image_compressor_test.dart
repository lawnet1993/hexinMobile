import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/media/mobile_image_compressor.dart';
import 'package:hexing_terminal_mobile/core/media/mobile_upload_policy.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'startup cleanup removes only incomplete mobile image directories',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'image-compressor-startup-cleanup-',
      );
      try {
        final incomplete = await Directory(
          path.join(root.path, 'mobile-image-source-interrupted'),
        ).create();
        await File(path.join(incomplete.path, 'source.jpg'))
            .writeAsBytes(List<int>.filled(64, 1));
        final unrelatedDirectory = await Directory(
          path.join(root.path, 'another-feature-cache'),
        ).create();
        final similarlyNamedFile = await File(
          path.join(root.path, 'mobile-image-source-keep.txt'),
        ).writeAsString('keep');
        final cutoff = DateTime.now();
        final currentProcessDirectory = await Directory(
          path.join(root.path, 'mobile-image-source-current-process'),
        ).create();

        await deleteIncompleteMobileImageSources(
          temporaryDirectoryLoader: () async => root,
          createdBefore: cutoff,
          modifiedAtLoader: (entity) async =>
              path.basename(entity.path) ==
                  'mobile-image-source-current-process'
              ? cutoff.add(const Duration(seconds: 1))
              : cutoff.subtract(const Duration(minutes: 2)),
        );

        expect(await incomplete.exists(), isFalse);
        expect(await currentProcessDirectory.exists(), isTrue);
        expect(await unrelatedDirectory.exists(), isTrue);
        expect(await similarlyNamedFile.exists(), isTrue);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('startup cleanup never deletes an active compression source', () async {
    final root = await Directory.systemTemp.createTemp(
      'image-compressor-active-cleanup-',
    );
    final encoderStarted = Completer<void>();
    final releaseEncoder = Completer<Uint8List>();
    try {
      final compressor = MobileImageCompressor(
        temporaryDirectoryLoader: () async => root,
        fileEncoder:
            (
              _, {
              required maxDimension,
              required quality,
              required webp,
            }) async {
              encoderStarted.complete();
              return releaseEncoder.future;
            },
      );
      final prepare = compressor.prepareStream(
        fileName: 'active.jpg',
        sourceLength: 3 * 1024 * 1024,
        openRead: () => Stream<List<int>>.value(Uint8List(3 * 1024 * 1024)),
        contentType: 'image/jpeg',
        purpose: MobileImagePurpose.message,
      );
      await encoderStarted.future;
      final active = await root
          .list()
          .where((entity) => entity is Directory)
          .single;

      await deleteIncompleteMobileImageSources(
        temporaryDirectoryLoader: () async => root,
        createdBefore: DateTime.now(),
        modifiedAtLoader: (_) async => DateTime(2000),
      );

      expect(await active.exists(), isTrue);
      releaseEncoder.complete(Uint8List(64));
      await prepare;
      expect(await active.exists(), isFalse);
    } finally {
      if (!releaseEncoder.isCompleted) releaseEncoder.complete(Uint8List(64));
      await root.delete(recursive: true);
    }
  });

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

  test('animated and vector images are preserved without encoding', () async {
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
    final source = Uint8List(3 * 1024 * 1024);

    for (final type in const ['image/gif', 'image/svg+xml']) {
      final result = await compressor.prepare(
        fileName: type == 'image/gif' ? 'animated.gif' : 'vector.svg',
        bytes: source,
        contentType: type,
        purpose: MobileImagePurpose.approval,
      );
      expect(identical(result.bytes, source), isTrue);
      expect(result.compressed, isFalse);
      expect(result.contentType, type);
    }
    expect(calls, 0);
  });

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

  test(
    'large stream uses file encoder and removes private temp source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'image-compressor-test-',
      );
      String? observedPath;
      var listCalls = 0;
      final source = Uint8List.fromList(
        List<int>.generate(2 * 1024 * 1024 + 1, (i) => i % 251),
      );
      final compressor = MobileImageCompressor(
        encoder:
            (
              bytes, {
              required maxDimension,
              required quality,
              required webp,
            }) async {
              listCalls++;
              return bytes;
            },
        fileEncoder:
            (
              sourcePath, {
              required maxDimension,
              required quality,
              required webp,
            }) async {
              observedPath = sourcePath;
              expect(await File(sourcePath).readAsBytes(), source);
              return Uint8List(128 * 1024);
            },
        temporaryDirectoryLoader: () async => root,
      );

      try {
        final result = await compressor.prepareStream(
          fileName: 'large.png',
          sourceLength: source.length,
          openRead: () => Stream<List<int>>.fromIterable([
            source.sublist(0, 1024),
            source.sublist(1024),
          ]),
          contentType: 'image/png',
          purpose: MobileImagePurpose.approval,
        );

        expect(listCalls, 0);
        expect(result.compressed, isTrue);
        expect(result.fileName, 'large.jpg');
        expect(result.bytes.length, 128 * 1024);
        expect(observedPath, isNotNull);
        expect(File(observedPath!).existsSync(), isFalse);
        expect(root.listSync(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'avatar crop source is always sampled before opening the cropper',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avatar-crop-source-test-',
      );
      var calls = 0;
      final source = Uint8List(100);
      final compressor = MobileImageCompressor(
        fileEncoder:
            (
              sourcePath, {
              required maxDimension,
              required quality,
              required webp,
            }) async {
              calls++;
              expect(maxDimension, 1600);
              expect(webp, isFalse);
              // Even a larger encoded fixture must be selected: dimensional
              // sampling, not byte reduction, protects the native cropper.
              return Uint8List(200);
            },
        temporaryDirectoryLoader: () async => root,
      );

      try {
        final result = await compressor.prepareStream(
          fileName: 'portrait.jpg',
          sourceLength: source.length,
          openRead: () => Stream<List<int>>.value(source),
          contentType: 'image/jpeg',
          purpose: MobileImagePurpose.avatarCrop,
        );

        expect(calls, 1);
        expect(result.bytes.length, 200);
        expect(result.fileName, 'portrait.jpg');
        expect(result.contentType, 'image/jpeg');
        expect(result.compressed, isTrue);
        expect(root.listSync(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'large stream retries then reports a safe error and cleans temp',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'image-compressor-test-',
      );
      var calls = 0;
      final compressor = MobileImageCompressor(
        fileEncoder:
            (
              sourcePath, {
              required maxDimension,
              required quality,
              required webp,
            }) async {
              calls++;
              throw StateError('encoder failed');
            },
        temporaryDirectoryLoader: () async => root,
      );

      try {
        await expectLater(
          compressor.prepareStream(
            fileName: 'large.jpg',
            sourceLength: 2 * 1024 * 1024 + 1,
            openRead: () =>
                Stream<List<int>>.value(Uint8List(2 * 1024 * 1024 + 1)),
            contentType: 'image/jpeg',
            purpose: MobileImagePurpose.message,
          ),
          throwsA(
            isA<MobileUploadProcessingException>().having(
              (error) => error.message,
              'message',
              '图片处理失败，请重新选择或换一张图片',
            ),
          ),
        );
        expect(calls, 4);
        expect(root.listSync(), isEmpty);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('an in-memory image retries a smaller attempt after failure', () async {
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
            if (calls == 1) throw StateError('temporary decoder pressure');
            return Uint8List(512 * 1024);
          },
    );

    final result = await compressor.prepare(
      fileName: 'camera.jpg',
      bytes: Uint8List(4 * 1024 * 1024),
      contentType: 'image/jpeg',
      purpose: MobileImagePurpose.message,
    );

    expect(calls, 2);
    expect(result.compressed, isTrue);
    expect(result.bytes.length, 512 * 1024);
  });

  test('large raster geometry uses power-of-two native decode sampling', () {
    expect(
      mobileImageSampledGeometry(width: 6000, height: 4000, maxDimension: 2560),
      (width: 2560, height: 1707, sampleSize: 2),
    );
    expect(
      mobileImageSampledGeometry(width: 4032, height: 3024, maxDimension: 2560),
      (width: 2560, height: 1920, sampleSize: 1),
    );
    expect(
      mobileImageSampledGeometry(width: 8000, height: 6000, maxDimension: 256),
      (width: 256, height: 192, sampleSize: 16),
    );
  });
}

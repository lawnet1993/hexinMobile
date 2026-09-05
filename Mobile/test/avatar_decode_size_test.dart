import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/shared/widgets/avatar_memory_image.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String square;
  late String landscape;
  setUpAll(() async {
    square = await imageData(2048, 2048);
    landscape = await imageData(400, 200);
  });
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('decode policy covers portraits without stretching or upscaling', () {
    final portrait = AvatarMemoryImage.targetSize(200, 400, 96);
    expect([portrait.width, portrait.height], [96, 192]);
    final small = AvatarMemoryImage.targetSize(20, 10, 96);
    expect([small.width, small.height], [20, 10]);
  });
  test(
    'extreme panorama is bounded even when cover would require more pixels',
    () {
      final result = AvatarMemoryImage.targetSize(65536, 64, 96);
      expect([result.width, result.height], [1024, 1]);
      expect(
        () => AvatarMemoryImage.targetSize(0, 10, 96),
        throwsArgumentError,
      );
    },
  );
  test('decode size buckets handle fractional scale, absent scale and extreme size', () {
    expect(AvatarMemoryImage.decodeDiameter(17, 2.625), 96);
    expect(AvatarMemoryImage.decodeDiameter(18, 2.625), 96);
    expect(AvatarMemoryImage.decodeDiameter(1000, 10), 512);
    expect(AvatarMemoryImage.decodeDiameter(16, double.nan), 32);
    expect(AvatarMemoryImage.decodeDiameter(double.infinity, 1), 32);
  });
  test(
    'decoded cache distinguishes content and size from full-size MemoryImage',
    () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final small = AvatarMemoryImage(bytes, diameter: 96);
      final same = AvatarMemoryImage(bytes, diameter: 96);
      final large = AvatarMemoryImage(bytes, diameter: 192);
      expect(small, same);
      expect(small.hashCode, same.hashCode);
      expect(small, isNot(large));
      expect(small, isNot(MemoryImage(bytes)));
      expect(MemoryImage(bytes), isNot(small));
      expect(
        small,
        isNot(AvatarMemoryImage(Uint8List.fromList([4]), diameter: 96)),
      );
    },
  );

  Future<ImageProvider<Object>> mount(
    WidgetTester tester,
    String data, {
    double radius = 16,
    double dpr = 3,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: dpr),
          child: Scaffold(
            body: InitialAvatar(
              name: 'AI-UAT',
              avatarDataUrl: data,
              radius: radius,
            ),
          ),
        ),
      ),
    );
    return tester
        .widget<CircleAvatar>(find.byType(CircleAvatar))
        .foregroundImage!;
  }

  testWidgets(
    'small avatar decodes to physical size instead of the full photo',
    (tester) async {
      final provider = await mount(tester, square);
      final info = (await tester.runAsync(() => resolveImage(provider)))!;
      try {
        expect([info.image.width, info.image.height], [96, 96]);
      } finally {
        info.dispose();
      }
    },
  );

  testWidgets(
    'same photo and decode size reuse the image key across rebuilds',
    (tester) async {
      final first = await mount(tester, square);
      final second = await mount(tester, square);
      expect(
        await first.obtainKey(ImageConfiguration.empty),
        await second.obtainKey(ImageConfiguration.empty),
      );
    },
  );

  testWidgets('header and list avatars have distinct resolution-aware keys', (
    tester,
  ) async {
    final small = await mount(tester, square);
    final header = await mount(tester, square, radius: 32);
    expect(
      await small.obtainKey(ImageConfiguration.empty),
      isNot(await header.obtainKey(ImageConfiguration.empty)),
    );
  });

  testWidgets('non-square photo preserves aspect and enough pixels for cover', (
    tester,
  ) async {
    final provider = await mount(tester, landscape);
    final info = (await tester.runAsync(() => resolveImage(provider)))!;
    try {
      expect([info.image.width, info.image.height], [192, 96]);
    } finally {
      info.dispose();
    }
  });
}

Future<String> imageData(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return 'data:image/png;base64,${base64Encode(Uint8List.sublistView(bytes))}';
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<ImageInfo> resolveImage(ImageProvider<Object> provider) {
  final result = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!result.isCompleted) result.complete(info.clone());
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stack) {
      if (!result.isCompleted) result.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return result.future;
}

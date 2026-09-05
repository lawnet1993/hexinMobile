import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hexing_terminal_mobile/shared/widgets/avatar_memory_image.dart';
import 'package:hexing_terminal_mobile/shared/widgets/terminal_avatar_assets.dart';
import 'package:path_provider/path_provider.dart';

/// Opt-in, non-release entry point. Uses bundled/synthetic portraits only;
/// never opens account storage, the network, or a business database.
Future<void> main() async {
  if (kReleaseMode) throw UnsupportedError('Profile-only avatar benchmark');
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('AI-UAT 头像解码测试'))),
    ),
  );
  try {
    final preset = terminalAvatarDataUrls['person']!;
    final fixtures = <String, Uint8List>{
      'bundled-preset': base64Decode(preset.substring(preset.indexOf(',') + 1)),
      'synthetic-square': await _image(2048, 2048),
      'synthetic-landscape': await _image(4096, 2048),
      'synthetic-portrait': await _image(2048, 4096),
    };
    final results = <Map<String, Object>>[];
    for (final fixture in fixtures.entries) {
      final old = await _measure(MemoryImage(fixture.value));
      final sized = await _measure(
        AvatarMemoryImage(fixture.value, diameter: 96),
      );
      results.add({
        'fixture': fixture.key,
        'targetDiameterPixels': 96,
        'original': old,
        'sized': sized,
      });
    }
    final directory = await getTemporaryDirectory();
    final report = File(
      '${directory.path}/ai-uat-avatar-result-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope': 'Bundled/synthetic ImageProvider resolution only, not page raster or GPU allocation',
        'results': results,
      }),
    );
    debugPrint('AVATAR_DECODE_BENCHMARK_RESULT ${report.path}');
    runApp(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('AI-UAT 解码对照')),
          body: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('左：原图解码　右：按头像尺寸解码'),
              ),
              for (final fixture in fixtures.entries)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(fixture.key),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            foregroundImage: MemoryImage(fixture.value),
                          ),
                          CircleAvatar(
                            radius: 24,
                            foregroundImage: AvatarMemoryImage(
                              fixture.value,
                              diameter: 128,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  } catch (_) {
    debugPrint('AVATAR_DECODE_BENCHMARK_FAILED');
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('AI-UAT 头像解码测试失败'))),
      ),
    );
  }
}

Future<Map<String, Object>> _measure(ImageProvider<Object> provider) async {
  final times = <int>[];
  int? width;
  int? height;
  for (var i = 0; i < 5; i++) {
    await provider.evict();
    final timer = Stopwatch()..start();
    final stream = provider.resolve(ImageConfiguration.empty);
    final result = Completer<ImageInfo>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!result.isCompleted) result.complete(info.clone());
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stack) {
        if (!result.isCompleted) {
          result.completeError(StateError('Fixture decode failed'));
        }
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final info = await result.future;
    timer.stop();
    width = info.image.width;
    height = info.image.height;
    info.dispose();
    times.add(timer.elapsedMicroseconds);
  }
  await provider.evict();
  final sorted = [...times]..sort();
  return {
    'width': width!,
    'height': height!,
    'decodedRgbaBytes': width * height * 4,
    'coldResolveMicros': times,
    'medianColdResolveMicros': sorted[2],
  };
}

Future<Uint8List> _image(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.blue,
  );
  canvas.drawCircle(
    Offset(width / 2, height / 2),
    height / 4,
    Paint()..color = Colors.white,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    return Uint8List.sublistView(
      (await image.toByteData(format: ui.ImageByteFormat.png))!,
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

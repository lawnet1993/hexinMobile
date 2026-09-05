import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'im_window_benchmark_fixture.dart';

/// Explicit diagnostic entry point; never imported by lib/main.dart.
Future<void> main() async {
  if (kReleaseMode) {
    throw UnsupportedError('Benchmark is not a release entry point');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('AI-UAT 本地消息查询测试'))),
    ),
  );
  final cache = await getTemporaryDirectory();
  final directory = await cache.createTemp('ai-uat-window-');
  try {
    final result = await runImWindowBenchmark(databaseFactory, directory);
    // Only synthetic numeric results and SQL plans, never real payloads or IDs.
    final report = File(
      '${cache.path}/ai-uat-window-result-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
    );
    debugPrint('IM_WINDOW_BENCHMARK_RESULT ${report.path}');
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('AI-UAT 本地查询验证通过'))),
      ),
    );
  } catch (_) {
    debugPrint('IM_WINDOW_BENCHMARK_FAILED');
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('AI-UAT 本地查询验证失败'))),
      ),
    );
  } finally {
    // This is exclusively the directory created above, not the app cache root.
    await directory.delete(recursive: true);
  }
}

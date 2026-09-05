import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../tool/im_window_benchmark_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('benchmark exercises production query, encrypted model and old-index control', () async {
    final dir = await Directory.systemTemp.createTemp('ai-uat-benchmark-test-');
    try {
      final result = await runImWindowBenchmark(
        databaseFactoryFfi,
        dir,
        sizes: [1000],
      );
      expect(result['schemaVersion'], 15);
      expect(
        (result['results'] as List).single,
        containsPair('sameRowsAndReceipts', true),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

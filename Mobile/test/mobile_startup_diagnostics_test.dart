import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/diagnostics/mobile_startup_diagnostics.dart';

void main() {
  test('empty timings remain unknown rather than zero milliseconds', () {
    final result = StartupFrameSamples(refreshRate: 60).summary();
    expect(result['sampleCount'], 0);
    expect(result['firstFrame'], isNull);
    expect((result['build'] as Map)['maxMicros'], isNull);
  });
  test('nearest rank percentiles separate UI, raster and total latency', () {
    final samples = StartupFrameSamples(refreshRate: 60);
    for (final n in [4, 1, 3, 2]) {
      samples.add(_frame(build: n * 10000, raster: n * 20000));
    }
    final result = samples.summary();
    expect(result['frameBudgetMicros'], 16667);
    expect(result['build'], {
      'p50Micros': 20000,
      'p95Micros': 40000,
      'maxMicros': 40000,
      'overBudgetCount': 3,
    });
    expect((result['raster'] as Map)['p50Micros'], 40000);
    expect((result['totalSpan'] as Map)['maxMicros'], 120000);
    expect((result['firstFrame'] as Map)['buildMicros'], 40000);
  });
  test('sample memory is bounded and later frames do not alter statistics', () {
    final samples = StartupFrameSamples(refreshRate: 120, maxSamples: 2);
    samples.add(_frame(build: 9000));
    samples.add(_frame(build: 1000));
    final before = jsonEncode(samples.summary());
    samples.add(_frame(build: 999999));
    expect(samples.isFull, isTrue);
    expect(jsonEncode(samples.summary()), before);
    expect((samples.summary()['build'] as Map)['overBudgetCount'], 1);
  });
  for (final rate in [double.nan, double.infinity, 0.0, -1.0, 1001.0]) {
    test('invalid display refresh rate $rate falls back to 60Hz', () {
      expect(
        StartupFrameSamples(refreshRate: rate).summary()['refreshRateHz'],
        60,
      );
    });
  }
  test('invalid durations are excluded and counted', () {
    final samples = StartupFrameSamples(refreshRate: 60);
    samples.add(_frame(build: -1));
    expect(samples.summary()['sampleCount'], 0);
    expect(samples.summary()['invalidSamples'], 1);
  });
  test('timing output contains only allowlisted numeric fields', () {
    final samples = StartupFrameSamples(refreshRate: 90)
      ..add(_frame(build: 1000));
    void numericTree(Object? node) {
      if (node is Map) {
        for (final value in node.values) {
          numericTree(value);
        }
      } else {
        expect(node == null || node is num, isTrue);
      }
    }

    numericTree(samples.summary());
    expect(
      samples.summary().keys,
      unorderedEquals([
        'sampleCount',
        'maxSamples',
        'invalidSamples',
        'refreshRateHz',
        'frameBudgetMicros',
        'build',
        'raster',
        'totalSpan',
        'vsyncOverhead',
        'firstFrame',
      ]),
    );
  });
  test('diagnostic callback is not installed in non-profile widget tests', () {
    expect(MobileStartupDiagnostics.install(), isNull);
  });
}

FrameTiming _frame({int build = 1000, int raster = 1000}) => FrameTiming(
  vsyncStart: 1000000,
  buildStart: 1000000,
  buildFinish: 1000000 + build,
  rasterStart: 1000000 + build,
  rasterFinish: 1000000 + build + raster,
  rasterFinishWallTime: 1000000 + build + raster,
);

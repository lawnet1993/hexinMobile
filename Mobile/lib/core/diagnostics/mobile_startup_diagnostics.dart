import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum MobileStartupStage {
  dartMain,
  runAppReturned,
  firstFrameworkFrame,
  secureSessionHydrated,
  shellCreated,
  shellFirstFrame,
  workbenchCacheReady,
  collaborationSyncRequested,
}

/// Bounded, numeric-only startup diagnostics. No VM service, account data,
/// message bodies, URLs or credentials; entirely disabled in release/debug.
final class MobileStartupDiagnostics {
  MobileStartupDiagnostics._() {
    _clock.start();
    _samples = StartupFrameSamples(
      refreshRate:
          WidgetsBinding
              .instance
              .platformDispatcher
              .implicitView
              ?.display
              .refreshRate ??
          60,
    );
    mark(MobileStartupStage.dartMain);
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      mark(MobileStartupStage.firstFrameworkFrame);
    });
    _timeout = Timer(
      const Duration(seconds: 15),
      () => _finish('window_elapsed'),
    );
  }

  static bool _installed = false;
  static MobileStartupDiagnostics? _current;

  static MobileStartupDiagnostics? install() {
    if (!kProfileMode || _installed) return null;
    _installed = true;
    return _current = MobileStartupDiagnostics._();
  }

  /// Records a process-wide startup milestone when profile diagnostics are
  /// active. Each milestone is emitted at most once and carries no user or
  /// business data.
  static void markCurrent(MobileStartupStage stage) => _current?.mark(stage);

  final Stopwatch _clock = Stopwatch();
  late final StartupFrameSamples _samples;
  Timer? _timeout;
  bool _finished = false;
  final Set<MobileStartupStage> _markedStages = {};

  void mark(MobileStartupStage stage) {
    if (!_markedStages.add(stage)) return;
    debugPrint(
      'MOBILE_STARTUP ${jsonEncode({'stage': stage.name, 'elapsedMicros': _clock.elapsedMicroseconds})}',
    );
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_finished) return;
    for (final timing in timings) {
      _samples.add(timing);
    }
    if (_samples.isFull) _finish('sample_limit');
  }

  void _finish(String reason) {
    if (_finished) return;
    _finished = true;
    _timeout?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    debugPrint(
      'MOBILE_STARTUP_FRAMES ${jsonEncode({'reason': reason, 'elapsedMicros': _clock.elapsedMicroseconds, ..._samples.summary()})}',
    );
    _clock.stop();
  }
}

/// Store only timings. Percentiles use nearest rank; an empty sample reports
/// null durations instead of claiming zero-cost rendering.
final class StartupFrameSamples {
  StartupFrameSamples({required double refreshRate, this.maxSamples = 240})
    : refreshRate =
          refreshRate.isFinite && refreshRate >= 1 && refreshRate <= 1000
          ? refreshRate
          : 60 {
    if (maxSamples < 1 || maxSamples > 1000) {
      throw ArgumentError.value(maxSamples);
    }
  }

  final double refreshRate;
  final int maxSamples;
  final List<({int build, int raster, int total, int vsync})> _frames = [];
  int invalidSamples = 0;

  bool get isFull => _frames.length >= maxSamples;

  void add(FrameTiming timing) {
    if (isFull) return;
    final frame = (
      build: timing.buildDuration.inMicroseconds,
      raster: timing.rasterDuration.inMicroseconds,
      total: timing.totalSpan.inMicroseconds,
      vsync: timing.vsyncOverhead.inMicroseconds,
    );
    if (frame.build < 0 ||
        frame.raster < 0 ||
        frame.vsync < 0 ||
        frame.total < frame.build ||
        frame.total < frame.raster) {
      invalidSamples++;
      return;
    }
    _frames.add(frame);
  }

  Map<String, Object?> summary() {
    final budget = (1000000 / refreshRate).round();
    return {
      'sampleCount': _frames.length,
      'maxSamples': maxSamples,
      'invalidSamples': invalidSamples,
      'refreshRateHz': refreshRate,
      'frameBudgetMicros': budget,
      'build': _stats(_frames.map((f) => f.build), budget),
      'raster': _stats(_frames.map((f) => f.raster), budget),
      'totalSpan': _stats(_frames.map((f) => f.total), budget),
      'vsyncOverhead': _stats(_frames.map((f) => f.vsync), budget),
      'firstFrame': _frames.isEmpty
          ? null
          : {
              'buildMicros': _frames.first.build,
              'rasterMicros': _frames.first.raster,
              'totalSpanMicros': _frames.first.total,
              'vsyncOverheadMicros': _frames.first.vsync,
            },
    };
  }

  Map<String, Object?> _stats(Iterable<int> values, int budget) {
    final sorted = values.toList()..sort();
    int? percentile(double p) =>
        sorted.isEmpty ? null : sorted[(sorted.length * p).ceil() - 1];
    return {
      'p50Micros': percentile(.5),
      'p95Micros': percentile(.95),
      'maxMicros': sorted.isEmpty ? null : sorted.last,
      'overBudgetCount': sorted.where((value) => value > budget).length,
    };
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'mobile_startup_diagnostics.dart';

enum ChatOpenStage {
  tap,
  keyboardHidden,
  navigationRequested,
  routeMounted,
  routeFrame,
  messagesAvailable,
  latestMessageLaidOut,
}

/// Numeric, first-occurrence-only checkpoints; never accepts an account, route,
/// message, URL or free-form label. Independently testable without a device.
final class ChatOpenMeasurement {
  final Map<ChatOpenStage, int> _stages = {ChatOpenStage.tap: 0};
  bool? cacheHit;
  int? messageCount;

  void mark(ChatOpenStage stage, int elapsedMicros) {
    if (elapsedMicros < 0 || _stages.containsKey(stage)) return;
    if (_stages.values.any((value) => value > elapsedMicros)) return;
    _stages[stage] = elapsedMicros;
  }

  void snapshot({required bool cached, required int count, required int at}) {
    if (messageCount != null ||
        count < 0 ||
        at < 0 ||
        _stages.values.any((value) => value > at)) {
      return;
    }
    cacheHit = cached;
    messageCount = count;
    mark(ChatOpenStage.messagesAvailable, at);
  }

  Map<String, Object?> summary() => {
    'cacheHit': cacheHit,
    'messageCount': messageCount,
    'stagesMicros': {
      for (final entry in _stages.entries) entry.key.name: entry.value,
    },
  };
}

enum ChatOpenEnd { windowElapsed, routeClosed, superseded }

/// Profile-only, at most 25 opens per process, one 3s/240-frame buffer at a time.
/// The conversation key exists only in memory for matching the actual route;
/// it is cleared on finish and never passed to the logger.
final class ChatOpenDiagnostics {
  ChatOpenDiagnostics._(this.sampleId) {
    _clock.start();
    _frames = StartupFrameSamples(
      refreshRate:
          WidgetsBinding
              .instance
              .platformDispatcher
              .implicitView
              ?.display
              .refreshRate ??
          60,
    );
    WidgetsBinding.instance.addTimingsCallback(_onFrames);
    _timer = Timer(
      const Duration(seconds: 3),
      () => finish(ChatOpenEnd.windowElapsed),
    );
  }

  static ChatOpenDiagnostics? _active;
  static int _issued = 0;
  static ChatOpenDiagnostics? begin() {
    if (!kProfileMode || _issued >= 25) return null;
    _active?.finish(ChatOpenEnd.superseded);
    return _active = ChatOpenDiagnostics._(++_issued);
  }

  static ChatOpenDiagnostics? attach(String conversationId) {
    final active = _active;
    if (active == null ||
        active._ended ||
        active._conversationId != conversationId) {
      return null;
    }
    active.mark(ChatOpenStage.routeMounted);
    return active;
  }

  final int sampleId;
  final _clock = Stopwatch();
  final _measurement = ChatOpenMeasurement();
  late final StartupFrameSamples _frames;
  Timer? _timer;
  String? _conversationId;
  bool _ended = false;

  void bind(String conversationId) {
    if (_ended) return;
    _conversationId = conversationId;
    mark(ChatOpenStage.navigationRequested);
  }

  void mark(ChatOpenStage stage) {
    if (!_ended) _measurement.mark(stage, _clock.elapsedMicroseconds);
  }

  void snapshot({required bool cached, required int count}) {
    if (!_ended) {
      _measurement.snapshot(
        cached: cached,
        count: count,
        at: _clock.elapsedMicroseconds,
      );
    }
  }

  void _onFrames(List<FrameTiming> timings) {
    if (_ended) return;
    for (final timing in timings) {
      _frames.add(timing);
    }
  }

  void finish(ChatOpenEnd reason) {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_onFrames);
    _conversationId = null;
    if (identical(_active, this)) _active = null;
    debugPrint(
      'MOBILE_CHAT_OPEN ${jsonEncode({'sampleId': sampleId, 'reason': reason.name, 'elapsedMicros': _clock.elapsedMicroseconds, ..._measurement.summary(), 'frames': _frames.summary()})}',
    );
    _clock.stop();
  }
}

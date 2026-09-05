import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Successful batch timings only, never payloads, URLs, IDs or credentials.
/// Disabled in release builds; empty long polls do not produce log traffic.
void recordOaSyncTiming({
  required int eventCount,
  required int waitSeconds,
  required int requestMilliseconds,
  required int projectionMilliseconds,
  required int commitMilliseconds,
}) {
  if (kReleaseMode || eventCount <= 0) return;
  debugPrint(
    'MOBILE_OA_SYNC ${jsonEncode({'recordedAt': DateTime.now().toUtc().toIso8601String(), 'eventCount': eventCount, 'waitSeconds': waitSeconds, 'requestMs': requestMilliseconds, 'projectionMs': projectionMilliseconds, 'commitMs': commitMilliseconds, 'totalMs': requestMilliseconds + projectionMilliseconds + commitMilliseconds, 'outcome': 'committed'})}',
  );
}

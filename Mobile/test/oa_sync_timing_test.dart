import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_sync_timing.dart';

void main() {
  test(
    'OA timing logs only explicit numeric diagnostics after nonempty batches',
    () {
      final previous = debugPrint;
      final lines = <String?>[];
      debugPrint = (message, {wrapWidth}) => lines.add(message);
      addTearDown(() => debugPrint = previous);
      recordOaSyncTiming(
        eventCount: 4,
        waitSeconds: 20,
        requestMilliseconds: 15000,
        projectionMilliseconds: 350,
        commitMilliseconds: 12,
      );
      expect(lines, hasLength(1));
      const prefix = 'MOBILE_OA_SYNC ';
      expect(lines.single, startsWith(prefix));
      final body = jsonDecode(lines.single!.substring(prefix.length)) as Map;
      expect(body.keys.toSet(), {
        'recordedAt',
        'eventCount',
        'waitSeconds',
        'requestMs',
        'projectionMs',
        'commitMs',
        'totalMs',
        'outcome',
      });
      expect(body['totalMs'], 15362);
      expect(body['outcome'], 'committed');
      expect(DateTime.parse(body['recordedAt'] as String).isUtc, true);
    },
  );

  test('OA empty polls do not emit periodic log noise', () {
    final previous = debugPrint;
    final lines = <String?>[];
    debugPrint = (message, {wrapWidth}) => lines.add(message);
    addTearDown(() => debugPrint = previous);
    recordOaSyncTiming(
      eventCount: 0,
      waitSeconds: 20,
      requestMilliseconds: 20000,
      projectionMilliseconds: 0,
      commitMilliseconds: 0,
    );
    expect(lines, isEmpty);
  });
}

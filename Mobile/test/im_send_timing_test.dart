import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_send_timing.dart';

void main() {
  test('send timing emits only bounded non-sensitive stage metrics', () {
    final lines = <String>[];
    final timing = ImSendTiming(write: lines.add);

    timing.recordForTest(
      kind: 'text',
      attempts: 1,
      queueMs: 12,
      requestMs: 34,
      commitMs: 5,
      totalMs: 51,
    );

    expect(lines, hasLength(1));
    const prefix = 'MOBILE_IM_SEND_STAGE ';
    expect(lines.single, startsWith(prefix));
    final body = jsonDecode(lines.single.substring(prefix.length)) as Map;
    expect(body, {
      'kind': 'text',
      'attempts': 1,
      'queueMs': 12,
      'requestMs': 34,
      'commitMs': 5,
      'totalMs': 51,
      'outcome': 'sent',
    });
    expect(lines.single, isNot(contains('conversation')));
    expect(lines.single, isNot(contains('messageId')));
    expect(lines.single, isNot(contains('token')));
  });

  test('send timing normalizes unknown kinds and clamps values', () {
    final lines = <String>[];
    ImSendTiming(write: lines.add).recordForTest(
      kind: 'secret-kind',
      attempts: -1,
      queueMs: -2,
      requestMs: 999999,
      commitMs: 999999,
      totalMs: 999999999,
    );

    final body = jsonDecode(
      lines.single.substring('MOBILE_IM_SEND_STAGE '.length),
    ) as Map;
    expect(body['kind'], 'other');
    expect(body['attempts'], 0);
    expect(body['queueMs'], 0);
    expect(body['requestMs'], 600000);
    expect(body['commitMs'], 600000);
    expect(body['totalMs'], 86400000);
  });
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

const imSendTiming = ImSendTiming();

/// Profile-only IM send stage metrics. The record deliberately excludes
/// account, conversation, message, device, URL, body and attachment identity.
class ImSendTiming {
  const ImSendTiming({this.write});

  final void Function(String)? write;

  void success({
    required String kind,
    required int attempts,
    required int queueMs,
    required int requestMs,
    required int commitMs,
    required int totalMs,
  }) {
    if (!kProfileMode) return;
    recordForTest(
      kind: kind,
      attempts: attempts,
      queueMs: queueMs,
      requestMs: requestMs,
      commitMs: commitMs,
      totalMs: totalMs,
    );
  }

  void recordForTest({
    required String kind,
    required int attempts,
    required int queueMs,
    required int requestMs,
    required int commitMs,
    required int totalMs,
  }) {
    const allowedKinds = {'text', 'file', 'image', 'video', 'audio', 'contact'};
    final record = <String, Object>{
      'kind': allowedKinds.contains(kind) ? kind : 'other',
      'attempts': attempts.clamp(0, 100),
      'queueMs': queueMs.clamp(0, 86400000),
      'requestMs': requestMs.clamp(0, 600000),
      'commitMs': commitMs.clamp(0, 600000),
      'totalMs': totalMs.clamp(0, 86400000),
      'outcome': 'sent',
    };
    (write ?? debugPrint)('MOBILE_IM_SEND_STAGE ${jsonEncode(record)}');
  }
}

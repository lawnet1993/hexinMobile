import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../domain/collaboration_models.dart';

/// Opt-in cursor provenance for device acceptance. Never logs payloads,
/// identities, headers, message text or attachment locations; disabled in release.
final class ImReadDiagnostics {
  ImReadDiagnostics({
    bool enabled = const bool.fromEnvironment('IM_READ_DIAGNOSTICS'),
    void Function(String)? sink,
  }) : _enabled = enabled && !kReleaseMode,
       _sink = sink ?? ((line) => debugPrint(line));

  final bool _enabled;
  final void Function(String) _sink;
  final Map<String, (int, int, int)> _snapshots = {};

  void snapshot(String source, int? status, List<ImConversation> values) {
    if (!_enabled) return;
    for (final value in values) {
      final key = '$source:${value.id}';
      final next = (
        value.lastMessageSequence,
        value.lastReadSequence,
        value.unreadCount,
      );
      if (_snapshots[key] == next) continue;
      // Bound diagnostics memory independently of conversation count.
      if (_snapshots.length >= 512) _snapshots.remove(_snapshots.keys.first);
      _snapshots[key] = next;
      _emit(source, value.id, {
        'status': status,
        'last': next.$1,
        'read': next.$2,
        'unread': next.$3,
      });
    }
  }

  void action(String source, String conversationId, {int? sequence}) {
    if (!_enabled) return;
    _emit(source, conversationId, {'sequence': ?sequence});
  }

  void events(
    List<ImSyncEvent> events,
    String currentMemberId,
    String accountId,
  ) {
    if (!_enabled) return;
    for (final event in events) {
      if (event.type != 'conversation.read') continue;
      try {
        final raw = jsonDecode(event.payloadJson);
        if (raw is! Map) continue;
        final conversation = (raw['conversationId'] ?? raw['ConversationId'])
            ?.toString();
        final reader = (raw['readerId'] ?? raw['ReaderId'])?.toString();
        final sequence = int.tryParse(
          (raw['sequence'] ?? raw['Sequence'])?.toString() ?? '',
        );
        if (conversation == null || sequence == null) continue;
        _emit('read_event', conversation, {
          'eventSequence': event.sequence,
          'sequence': sequence,
          'isSelf': reader == currentMemberId || reader == accountId,
        });
      } on FormatException {
        // Malformed events must not make diagnostics fail synchronization.
      }
    }
  }

  void _emit(
    String source,
    String conversationId,
    Map<String, Object?> values,
  ) {
    final tag = sha256
        .convert(utf8.encode(conversationId))
        .toString()
        .substring(0, 12);
    _sink(
      'MOBILE_IM_READ ${jsonEncode({'source': source, 'conversation': tag, ...values})}',
    );
  }
}

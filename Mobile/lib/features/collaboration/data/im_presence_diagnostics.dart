import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/collaboration_models.dart';
import 'im_member_presence.dart';
import 'im_presence_projection.dart';

const imPresenceDiagnostics = ImPresenceDiagnostics();

/// Opt-in, profile/debug-only field allowlist. Never accepts sessions, headers,
/// arbitrary response bodies, member names, message content or attachment URLs.
class ImPresenceDiagnostics {
  const ImPresenceDiagnostics({
    this.enabled = const bool.fromEnvironment('MOBILE_IM_PRESENCE_DIAGNOSTICS'),
    this.write,
  });
  final bool enabled;
  final void Function(String)? write;

  void response(
    ImConversationPresence value, {
    required int? status,
    required String host,
    required DateTime startedAt,
  }) {
    if (!enabled || kReleaseMode) return;
    _emit({
      'kind': 'response',
      'conversationId': value.conversationId,
      'conversationType': value.type,
      'httpStatus': status,
      'host': host,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'peerOnline': value.peerOnline,
      'peerPresenceKnown': value.peerPresenceKnown,
      'peerLastSeenAt': value.peerLastSeenAt?.toUtc().toIso8601String(),
      'onlineMemberCount': value.onlineMemberCount,
      'serverTime': value.serverTime?.toUtc().toIso8601String(),
    });
  }

  void render(
    String conversationId, {
    required bool? displayedOnline,
    required bool transportAvailable,
    required ImMemberPresenceObservation? member,
    required ImPresenceObservation? conversation,
  }) {
    if (!enabled || kReleaseMode) return;
    _emit({
      'kind': 'render',
      'conversationId': conversationId,
      'displayedOnline': displayedOnline,
      'transportAvailable': transportAvailable,
      'memberOnline': member?.online,
      'memberFresh': member?.fresh,
      'memberOrder': member?.order,
      'memberLastSeenAt': member?.lastSeenAt?.toUtc().toIso8601String(),
      'conversationOnline': conversation?.value.peerOnline,
      'conversationFresh': conversation?.fresh,
      'conversationServerTime': conversation?.value.serverTime
          ?.toUtc()
          .toIso8601String(),
    });
  }

  void _emit(Map<String, Object?> value) => (write ?? debugPrint)(
    'MOBILE_IM_PRESENCE ${jsonEncode({'sampledAt': DateTime.now().toUtc().toIso8601String(), ...value})}',
  );
}

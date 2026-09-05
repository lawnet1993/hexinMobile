import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/collaboration_models.dart';
import '../domain/presence_time.dart';
import 'im_member_presence.dart';

/// Live presence is ephemeral, unlike cached member identity and avatars.
/// Consumers share observations without initiating one HTTP request per row.
final imPresenceProjectionProvider =
    NotifierProvider<ImPresenceProjection, Map<String, ImPresenceObservation>>(
      ImPresenceProjection.new,
    );

class ImPresenceObservation {
  const ImPresenceObservation(this.value, {this.fresh = true});
  final ImConversationPresence value;
  final bool fresh;
}

class ImPresenceProjection
    extends Notifier<Map<String, ImPresenceObservation>> {
  final Map<String, Timer> _expiryTimers = {};

  @override
  Map<String, ImPresenceObservation> build() {
    // A same-account re-login/rotation must not inherit an earlier session's
    // claims about who is currently online.
    ref.watch(
      authControllerProvider.select(
        (value) => (
          value.value?.userId,
          value.value?.deviceId,
          value.value?.accessToken,
        ),
      ),
    );
    ref.onDispose(() {
      for (final timer in _expiryTimers.values) {
        timer.cancel();
      }
      _expiryTimers.clear();
    });
    return const {};
  }

  void observe(MobileSession session, ImConversationPresence value) {
    final current = ref.read(authControllerProvider).value;
    if (current == null ||
        !current.isSameSession(session) ||
        value.conversationId.isEmpty) {
      return;
    }
    final id = value.conversationId;
    final previous = state[id]?.value.serverTime;
    if (previous != null &&
        value.serverTime != null &&
        value.serverTime!.isBefore(previous)) {
      return;
    }
    final next = Map<String, ImPresenceObservation>.of(state)..remove(id);
    next[id] = ImPresenceObservation(value);
    // Bound memory independently of directory size or total conversation count.
    while (next.length > 128) {
      final oldest = next.keys.first;
      next.remove(oldest);
      _expiryTimers.remove(oldest)?.cancel();
    }
    _expiryTimers.remove(id)?.cancel();
    state = next;
    _expiryTimers[id] = Timer(const Duration(seconds: 60), () {
      _expiryTimers.remove(id);
      if (!ref.mounted || !identical(state[id]?.value, value)) return;
      state = {...state, id: ImPresenceObservation(value, fresh: false)};
    });
  }
}

({bool? online, DateTime? lastSeenAt}) resolveDirectPeerPresence({
  required bool transportAvailable,
  ImMember? member,
  ImMember? directoryMember,
  ImPresenceObservation? observation,
  ImMemberPresenceObservation? memberObservation,
  bool allowPreviewStatus = false,
}) {
  final peer = directoryMember?.id == member?.id
      ? directoryMember ?? member
      : member;
  final direct = observation?.value.type == 'direct' ? observation : null;
  if (memberObservation != null) {
    return resolveMemberPresence(
      transportAvailable: transportAvailable,
      member: peer,
      observation: memberObservation,
    );
  }
  final lastSeen = validPresenceTime(direct?.value.peerLastSeenAt) ??
      validPresenceTime(peer?.lastSeenAt);
  if (!transportAvailable || direct?.fresh == false) {
    return (online: null, lastSeenAt: lastSeen);
  }
  return (
    online: direct != null
        ? (direct.value.peerPresenceKnown ? direct.value.peerOnline : null)
        : (allowPreviewStatus ? peer?.isOnline : null),
    lastSeenAt: lastSeen,
  );
}

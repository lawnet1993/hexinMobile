import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/collaboration_models.dart';
import '../domain/presence_time.dart';

typedef ImMemberPresence = ({bool? online, DateTime? lastSeenAt});

final imMemberPresenceProjectionProvider =
    NotifierProvider<
      ImMemberPresenceProjection,
      Map<String, ImMemberPresenceObservation>
    >(ImMemberPresenceProjection.new);

/// Request order, not lastSeenAt or response arrival, orders local observations.
/// lastSeenAt is a server activity timestamp, not the time an offline sample was
/// taken. A delayed response must not revive an older online claim.
final class ImMemberPresenceRequest {
  ImMemberPresenceRequest._(this.order, this.generation);
  final int order;
  final Object generation;
  bool expired = false;
}

final class ImMemberPresenceObservation {
  const ImMemberPresenceObservation({
    required this.online,
    required this.order,
    this.lastSeenAt,
    this.fresh = true,
  });
  final bool? online;
  final int order;
  final DateTime? lastSeenAt;
  final bool fresh;

  ImMemberPresenceObservation expire() => ImMemberPresenceObservation(
    online: online,
    order: order,
    lastSeenAt: lastSeenAt,
    fresh: false,
  );
}

class ImMemberPresenceProjection
    extends Notifier<Map<String, ImMemberPresenceObservation>> {
  static const maximumMembers = 2048;
  static const maximumRequests = 128;
  static const lifetime = Duration(seconds: 60);
  final _requests = <ImMemberPresenceRequest, Timer>{};
  int _order = 0;
  Object _generation = Object();

  @override
  Map<String, ImMemberPresenceObservation> build() {
    ref.watch(
      authControllerProvider.select(
        (value) => (
          value.value?.userId,
          value.value?.deviceId,
          value.value?.accessToken,
        ),
      ),
    );
    _generation = Object();
    ref.onDispose(() {
      for (final entry in _requests.entries) {
        entry.key.expired = true;
        entry.value.cancel();
      }
      _requests.clear();
    });
    return const {};
  }

  ImMemberPresenceRequest beginRequest() {
    final request = ImMemberPresenceRequest._(++_order, _generation);
    // One timer per request batch, never one timer/HTTP call per member.
    _requests[request] = Timer(lifetime, () => _expire(request));
    while (_requests.length > maximumRequests) {
      _expire(_requests.keys.first);
    }
    return request;
  }

  void _expire(ImMemberPresenceRequest request) {
    request.expired = true;
    _requests.remove(request)?.cancel();
    if (!ref.mounted || !identical(request.generation, _generation)) return;
    if (!state.values.any(
      (value) => value.order == request.order && value.fresh,
    )) {
      return;
    }
    state = {
      for (final entry in state.entries)
        entry.key: entry.value.order == request.order
            ? entry.value.expire()
            : entry.value,
    };
  }

  void observe(
    MobileSession session,
    ImMemberPresenceRequest request,
    Iterable<ImMember> members,
  ) {
    if (!ref.mounted ||
        request.expired ||
        !identical(request.generation, _generation) ||
        ref.read(authControllerProvider).value?.isSameSession(session) !=
            true) {
      return;
    }
    final next = Map<String, ImMemberPresenceObservation>.of(state);
    var changed = false;
    for (final member in members) {
      if (member.id.isEmpty) continue;
      final previous = next[member.id];
      if (previous != null && previous.order >= request.order) continue;
      next.remove(member.id);
      next[member.id] = ImMemberPresenceObservation(
        online: member.presenceKnown ? member.isOnline : null,
        order: request.order,
        lastSeenAt: latestPresenceTime(previous?.lastSeenAt, member.lastSeenAt),
      );
      changed = true;
    }
    if (!changed) return;
    while (next.length > maximumMembers) {
      next.remove(next.keys.first);
    }
    state = next;
  }
}

DateTime? latestPresenceTime(DateTime? first, DateTime? second) {
  first = validPresenceTime(first);
  second = validPresenceTime(second);
  if (first == null) return second;
  if (second == null) return first;
  return first.isAfter(second) ? first : second;
}

/// Cached identity and last-seen history may be displayed offline. A cached
/// boolean alone never establishes current availability after a cold start.
ImMemberPresence resolveMemberPresence({
  required bool transportAvailable,
  ImMember? member,
  ImMemberPresenceObservation? observation,
  bool allowPreviewStatus = false,
}) => (
  online: !transportAvailable
      ? null
      : observation != null
      ? (observation.fresh ? observation.online : null)
      : (allowPreviewStatus ? member?.isOnline : null),
  lastSeenAt: latestPresenceTime(member?.lastSeenAt, observation?.lastSeenAt),
);

ImMemberPresence watchMemberPresence(
  WidgetRef ref,
  ImMember? member, {
  required bool transportAvailable,
}) => ref.watch(
  imMemberPresenceProjectionProvider.select(
    (values) => resolveMemberPresence(
      transportAvailable: transportAvailable,
      member: member,
      observation: values[member?.id],
      allowPreviewStatus: AppEnvironment.demoMode,
    ),
  ),
);

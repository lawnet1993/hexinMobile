import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/mobile_device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/managed_security_repository.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../data/collaboration_repositories.dart';

enum MobileImCursorHealth { healthy, ackPending, invalid, unavailable }

final class MobileImSyncHealth {
  const MobileImSyncHealth({
    required this.appliedSequence,
    required this.acknowledgedSequence,
    required this.cursorHealth,
  });

  const MobileImSyncHealth.unavailable()
    : appliedSequence = 0,
      acknowledgedSequence = 0,
      cursorHealth = MobileImCursorHealth.unavailable;

  factory MobileImSyncHealth.fromCursors({
    required int appliedSequence,
    required int acknowledgedSequence,
  }) {
    final health = acknowledgedSequence > appliedSequence
        ? MobileImCursorHealth.invalid
        : acknowledgedSequence < appliedSequence
        ? MobileImCursorHealth.ackPending
        : MobileImCursorHealth.healthy;
    return MobileImSyncHealth(
      appliedSequence: appliedSequence,
      acknowledgedSequence: acknowledgedSequence,
      cursorHealth: health,
    );
  }

  final int appliedSequence;
  final int acknowledgedSequence;
  final MobileImCursorHealth cursorHealth;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': 'http_long_poll',
    'appliedSequence': appliedSequence,
    'acknowledgedSequence': acknowledgedSequence,
    'pendingAckCount': acknowledgedSequence <= appliedSequence
        ? appliedSequence - acknowledgedSequence
        : 0,
    'cursorHealth': switch (cursorHealth) {
      MobileImCursorHealth.healthy => 'healthy',
      MobileImCursorHealth.ackPending => 'ack_pending',
      MobileImCursorHealth.invalid => 'invalid',
      MobileImCursorHealth.unavailable => 'unavailable',
    },
  };
}

typedef MobileImSyncHealthLoader = Future<MobileImSyncHealth> Function(
  MobileSession session,
);

final mobileImSyncHealthLoaderProvider = Provider<MobileImSyncHealthLoader>((
  ref,
) {
  return (session) async {
    final cursors = await ref
        .read(imLocalStoreProvider)
        .syncCursors(session.userId, session.syncDeviceId);
    return MobileImSyncHealth.fromCursors(
      appliedSequence: cursors.appliedSequence,
      acknowledgedSequence: cursors.acknowledgedSequence,
    );
  };
});

enum MobileOaSyncState { healthy, pendingUpload, unavailable }

final class MobileOaSyncHealth {
  const MobileOaSyncHealth({
    required this.appliedSequence,
    required this.pendingCommandCount,
    required this.pendingNotificationReadCount,
    required this.state,
  });

  const MobileOaSyncHealth.unavailable()
    : appliedSequence = 0,
      pendingCommandCount = 0,
      pendingNotificationReadCount = 0,
      state = MobileOaSyncState.unavailable;

  factory MobileOaSyncHealth.fromLocalState({
    required int appliedSequence,
    required int pendingCommandCount,
    required int pendingNotificationReadCount,
  }) => MobileOaSyncHealth(
    appliedSequence: appliedSequence,
    pendingCommandCount: pendingCommandCount,
    pendingNotificationReadCount: pendingNotificationReadCount,
    state: pendingCommandCount > 0 || pendingNotificationReadCount > 0
        ? MobileOaSyncState.pendingUpload
        : MobileOaSyncState.healthy,
  );

  final int appliedSequence;
  final int pendingCommandCount;
  final int pendingNotificationReadCount;
  final MobileOaSyncState state;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': 'http_long_poll',
    'appliedSequence': appliedSequence,
    'pendingCommandCount': pendingCommandCount,
    'pendingNotificationReadCount': pendingNotificationReadCount,
    'state': switch (state) {
      MobileOaSyncState.healthy => 'healthy',
      MobileOaSyncState.pendingUpload => 'pending_upload',
      MobileOaSyncState.unavailable => 'unavailable',
    },
  };
}

typedef MobileOaSyncHealthLoader = Future<MobileOaSyncHealth> Function(
  MobileSession session,
);

final mobileOaSyncHealthLoaderProvider = Provider<MobileOaSyncHealthLoader>((
  ref,
) {
  return (session) async {
    final state = await ref
        .read(oaLocalStoreProvider)
        .syncHealth(session.userId);
    return MobileOaSyncHealth.fromLocalState(
      appliedSequence: state.appliedSequence,
      pendingCommandCount: state.pendingCommandCount,
      pendingNotificationReadCount: state.pendingNotificationReadCount,
    );
  };
});

final mobilePresenceCoordinatorProvider = Provider<MobilePresenceCoordinator>((
  ref,
) {
  final coordinator = MobilePresenceCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final class MobilePresenceCoordinator {
  MobilePresenceCoordinator(this._ref);

  final Ref _ref;
  Timer? _timer;
  ({Future<void> result, CancelToken cancellation})? _active;
  bool _running = false;
  bool _disposed = false;
  int _epoch = 0;

  Future<void> start() async {
    if (_running || _disposed || !_ref.mounted) return;
    _running = true;
    final epoch = _epoch;
    await synchronizeNow();
    if (!_running || !_isCurrent(epoch)) return;
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => synchronizeNow().ignore(),
    );
  }

  void stop() {
    _epoch++;
    _running = false;
    _timer?.cancel();
    _timer = null;
    // Detach before cancellation. Old completions must not clear new handles.
    final active = _active;
    _active = null;
    active?.cancellation.cancel();
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  bool _isCurrent(int epoch) => !_disposed && _ref.mounted && epoch == _epoch;

  Future<void> synchronizeNow() {
    if (_disposed || !_ref.mounted) return Future<void>.value();
    final active = _active;
    if (active != null) return active.result;
    final epoch = _epoch;
    final cancellation = CancelToken();
    late final Future<void> result;
    result = _synchronize(epoch, cancellation).whenComplete(() {
      if (identical(_active?.result, result)) _active = null;
    });
    _active = (result: result, cancellation: cancellation);
    return result;
  }

  Future<void> _synchronize(int epoch, CancelToken cancellation) async {
    try {
      final session = await _ref
          .read(authControllerProvider.notifier)
          .maintainSession();
      if (!_isCurrent(epoch)) return;
      if (session == null || session.accessToken.isEmpty) return;
      final identity = await _ref.read(mobileDeviceIdentityProvider).resolve();
      if (!_isCurrent(epoch)) return;
      final latest = await _ref.read(secureSessionStoreProvider).readSession();
      if (!_isCurrent(epoch) ||
          latest == null ||
          !latest.isSameSession(session)) {
        return;
      }
      final policyVersion =
          _ref.read(managedPolicyStatusProvider).value?.policyVersion ?? '';
      final imSyncHealth = await _readImSyncHealth(latest);
      final oaSyncHealth = await _readOaSyncHealth(latest);
      if (!_isCurrent(epoch)) return;
      final response = await _ref
          .read(dioProvider)
          .post<void>(
            '/api/client/heartbeat',
            cancelToken: cancellation,
            data: {
              // The control plane authorizes heartbeats against the device
              // record returned by login. The stable installation id remains
              // separate and is reused in future login requests/local cursors.
              'deviceId': session.deviceId,
              'installationId': identity.installationId,
              'operatingSystem': identity.operatingSystem,
              'clientVersion': identity.clientVersion,
              'policyVersion': policyVersion,
              'systemProxyEnabled': false,
              // IM/OA mobile sessions never rely on the desktop site tunnel.
              'tunEnabled': false,
              'sentAt': DateTime.now().toUtc().toIso8601String(),
              'imSync': imSyncHealth.toJson(),
              'oaSync': oaSyncHealth.toJson(),
            },
            options: Options(
              contentType: Headers.jsonContentType,
              headers: {
                'Authorization': 'Bearer ${session.accessToken}',
                'X-Device-Id': session.deviceId,
              },
            ),
          );
      debugPrint(
        'MOBILE_COLLAB_SYNC_HEALTH ${jsonEncode({'heartbeatStatus': response.statusCode, 'im': imSyncHealth.toJson(), 'oa': oaSyncHealth.toJson()})}',
      );
    } on DioException catch (error) {
      if (!_isCurrent(epoch)) return;
      final disposition = classifyMobileHeartbeatFailure(error);
      if (disposition == MobileHeartbeatDisposition.sessionReplaced ||
          disposition == MobileHeartbeatDisposition.sessionExpired) {
        final terminated = await _ref
            .read(authControllerProvider.notifier)
            .handleSessionFailure(error);
        if (_isCurrent(epoch) && terminated) stop();
      }
      // Presence refresh is retried by the next heartbeat and app resume.
    } catch (_) {
      // Presence refresh is retried by the next heartbeat and app resume.
    }
  }

  Future<MobileImSyncHealth> _readImSyncHealth(MobileSession session) async {
    try {
      return await _ref.read(mobileImSyncHealthLoaderProvider)(session);
    } catch (_) {
      // Heartbeat must remain available even when the local IM cache cannot be
      // opened. The unavailable state is itself useful safe telemetry.
      return const MobileImSyncHealth.unavailable();
    }
  }

  Future<MobileOaSyncHealth> _readOaSyncHealth(MobileSession session) async {
    try {
      return await _ref.read(mobileOaSyncHealthLoaderProvider)(session);
    } catch (_) {
      // OA cache issues must not suppress the session heartbeat.
      return const MobileOaSyncHealth.unavailable();
    }
  }
}

enum MobileHeartbeatDisposition { retry, sessionReplaced, sessionExpired }

MobileHeartbeatDisposition classifyMobileHeartbeatFailure(DioException error) {
  final status = error.response?.statusCode;
  final body = error.response?.data;
  final code = body is Map
      ? (body['code'] ?? body['Code'])?.toString().trim().toLowerCase()
      : '';
  if (status == 409 && code == 'session_replaced') {
    return MobileHeartbeatDisposition.sessionReplaced;
  }
  if (status == 401) return MobileHeartbeatDisposition.sessionExpired;
  return MobileHeartbeatDisposition.retry;
}

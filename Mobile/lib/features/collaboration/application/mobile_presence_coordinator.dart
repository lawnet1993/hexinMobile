import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/mobile_device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/security/managed_security_repository.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../network/application/tunnel_controller.dart';

final mobilePresenceCoordinatorProvider = Provider<MobilePresenceCoordinator>((
  ref,
) {
  final coordinator = MobilePresenceCoordinator(ref);
  ref.onDispose(coordinator.stop);
  return coordinator;
});

final class MobilePresenceCoordinator {
  MobilePresenceCoordinator(this._ref);

  final Ref _ref;
  Timer? _timer;
  bool _syncing = false;
  bool _running = false;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await synchronizeNow();
    if (!_running) return;
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => synchronizeNow().ignore(),
    );
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> synchronizeNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final session = await _ref.read(secureSessionStoreProvider).readSession();
      if (session == null || session.accessToken.isEmpty) return;
      final identity = await _ref.read(mobileDeviceIdentityProvider).resolve();
      final policyVersion =
          _ref.read(managedPolicyStatusProvider).value?.policyVersion ?? '';
      final tunnelConnected =
          _ref.read(tunnelControllerProvider).value?.status.isConnected ??
          false;
      await _ref
          .read(dioProvider)
          .post<void>(
            '/api/client/heartbeat',
            data: {
              // The control plane authorizes heartbeats against the device
              // record returned by login. The stable installation id remains
              // separate and is reused in future login requests/local cursors.
              'deviceId': session.deviceId,
              'operatingSystem': identity.operatingSystem,
              'clientVersion': identity.clientVersion,
              'policyVersion': policyVersion,
              'systemProxyEnabled': false,
              'tunEnabled': tunnelConnected,
              'sentAt': DateTime.now().toUtc().toIso8601String(),
            },
            options: Options(contentType: Headers.jsonContentType),
          );
    } on DioException catch (error) {
      final disposition = classifyMobileHeartbeatFailure(error);
      if (disposition == MobileHeartbeatDisposition.sessionReplaced) {
        stop();
        await _ref
            .read(authControllerProvider.notifier)
            .terminateSession(message: '当前移动端已在另一台设备登录，请重新登录');
      } else if (disposition == MobileHeartbeatDisposition.sessionExpired) {
        stop();
        await _ref
            .read(authControllerProvider.notifier)
            .terminateSession(message: '登录已失效或已到期，请重新登录');
      }
      // Presence refresh is retried by the next heartbeat and app resume.
    } catch (_) {
      // Presence refresh is retried by the next heartbeat and app resume.
    } finally {
      _syncing = false;
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

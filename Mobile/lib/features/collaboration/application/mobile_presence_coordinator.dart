import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/network/api_client.dart';
import '../../../core/security/managed_security_repository.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../network/application/tunnel_controller.dart';
import '../data/collaboration_repositories.dart';

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

  Future<void> start() async {
    if (_timer != null) return;
    await synchronizeNow();
    _timer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => synchronizeNow().ignore(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> synchronizeNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final session = await _ref.read(secureSessionStoreProvider).readSession();
      if (session == null || session.accessToken.isEmpty) return;
      final package = await PackageInfo.fromPlatform();
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
              'deviceId': session.deviceId,
              'operatingSystem': Platform.isAndroid
                  ? 'Android'
                  : Platform.operatingSystem,
              'clientVersion': package.version,
              'policyVersion': policyVersion,
              'systemProxyEnabled': false,
              'tunEnabled': tunnelConnected,
              'sentAt': DateTime.now().toUtc().toIso8601String(),
            },
            options: Options(contentType: Headers.jsonContentType),
          );
      await _ref.read(imRepositoryProvider).refreshBootstrap();
      _ref.invalidate(imBootstrapProvider);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _ref.read(authControllerProvider.notifier).refreshSession();
      }
      // Presence refresh is retried by the next heartbeat and app resume.
    } catch (_) {
      // Presence refresh is retried by the next heartbeat and app resume.
    } finally {
      _syncing = false;
    }
  }
}

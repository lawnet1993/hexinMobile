import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/device/mobile_device_identity.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/mobile_presence_coordinator.dart';

void main() {
  test(
    'mobile login contract hardcodes platform and carries device identity',
    () {
      const identity = MobileDeviceIdentity(
        id: 'mobile-install-id',
        name: 'Android test device',
        fingerprint: 'stable-fingerprint',
        operatingSystem: 'Android 16',
        clientVersion: '1.2.3',
      );

      final payload = buildMobileLoginRequest(
        username: ' mobile-user ',
        password: 'test-password',
        identity: identity,
      );

      expect(payload['clientPlatform'], 'mobile');
      expect(payload['username'], 'mobile-user');
      expect(payload['deviceId'], identity.id);
      expect(payload['installationId'], identity.installationId);
      expect(payload['deviceName'], identity.name);
      expect(payload['fingerprint'], identity.fingerprint);
      expect(payload['operatingSystem'], 'Android 16');
      expect(payload['clientVersion'], '1.2.3');
    },
  );

  test('IM cursor telemetry reports monotonic health without identifiers', () {
    final healthy = MobileImSyncHealth.fromCursors(
      appliedSequence: 23,
      acknowledgedSequence: 23,
    ).toJson();
    final pending = MobileImSyncHealth.fromCursors(
      appliedSequence: 29,
      acknowledgedSequence: 23,
    ).toJson();
    final invalid = MobileImSyncHealth.fromCursors(
      appliedSequence: 23,
      acknowledgedSequence: 29,
    ).toJson();

    expect(healthy, containsPair('mode', 'http_long_poll'));
    expect(healthy, containsPair('cursorHealth', 'healthy'));
    expect(pending, containsPair('cursorHealth', 'ack_pending'));
    expect(pending, containsPair('pendingAckCount', 6));
    expect(invalid, containsPair('cursorHealth', 'invalid'));
    expect(invalid, containsPair('pendingAckCount', 0));
    expect(healthy.containsKey('deviceId'), isFalse);
    expect(healthy.containsKey('installationId'), isFalse);
  });

  test('OA telemetry reports event and pending mutation health', () {
    final healthy = MobileOaSyncHealth.fromLocalState(
      appliedSequence: 41,
      pendingCommandCount: 0,
      pendingNotificationReadCount: 0,
    ).toJson();
    final pending = MobileOaSyncHealth.fromLocalState(
      appliedSequence: 42,
      pendingCommandCount: 2,
      pendingNotificationReadCount: 1,
    ).toJson();

    expect(healthy, containsPair('mode', 'http_long_poll'));
    expect(healthy, containsPair('state', 'healthy'));
    expect(healthy, containsPair('appliedSequence', 41));
    expect(pending, containsPair('state', 'pending_upload'));
    expect(pending, containsPair('pendingCommandCount', 2));
    expect(pending, containsPair('pendingNotificationReadCount', 1));
    expect(pending.containsKey('accountId'), isFalse);
    expect(pending.containsKey('deviceId'), isFalse);
  });

  test('heartbeat only signs out for replaced or expired sessions', () {
    DioException failure(int status, Object? data) => DioException(
      requestOptions: RequestOptions(path: '/api/client/heartbeat'),
      response: Response<Object?>(
        requestOptions: RequestOptions(path: '/api/client/heartbeat'),
        statusCode: status,
        data: data,
      ),
      type: DioExceptionType.badResponse,
    );

    expect(
      classifyMobileHeartbeatFailure(
        failure(409, {'code': 'session_replaced'}),
      ),
      MobileHeartbeatDisposition.sessionReplaced,
    );
    expect(
      classifyMobileHeartbeatFailure(failure(401, null)),
      MobileHeartbeatDisposition.sessionExpired,
    );
    expect(
      classifyMobileHeartbeatFailure(failure(409, {'code': 'other'})),
      MobileHeartbeatDisposition.retry,
    );
    expect(
      classifyMobileHeartbeatFailure(failure(500, null)),
      MobileHeartbeatDisposition.retry,
    );
  });

  test('session termination notice is emitted once and consumed once', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notices = container.read(sessionTerminationNoticeProvider.notifier);

    notices.showOnce('当前移动端已在另一台设备登录，请重新登录');
    notices.showOnce('登录已失效或已到期，请重新登录');

    expect(
      container.read(sessionTerminationNoticeProvider),
      '当前移动端已在另一台设备登录，请重新登录',
    );
    expect(notices.take(), '当前移动端已在另一台设备登录，请重新登录');
    expect(notices.take(), isNull);

    notices.showOnce('登录已失效或已到期，请重新登录');
    notices.clear();
    expect(container.read(sessionTerminationNoticeProvider), isNull);
  });
}

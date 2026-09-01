import 'package:dio/dio.dart';
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
      expect(payload['deviceName'], identity.name);
      expect(payload['fingerprint'], identity.fingerprint);
      expect(payload['operatingSystem'], 'Android 16');
      expect(payload['clientVersion'], '1.2.3');
    },
  );

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
}

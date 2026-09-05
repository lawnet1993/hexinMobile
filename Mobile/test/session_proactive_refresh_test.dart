import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:hexing_terminal_mobile/core/network/api_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/mobile_presence_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restored session refreshes before heartbeat when expiry is near',
    () async {
      final rig = await _Rig.create();
      await rig.presence.synchronizeNow();
      expect(rig.refreshCalls, 1);
      expect(rig.heartbeatTokens, [rig.renewed.accessToken]);
      expect(rig.order, ['refresh', 'heartbeat']);
      expect(
        (await SecureSessionStore().readSession())?.accessToken,
        rig.renewed.accessToken,
      );
      expect(rig.container.read(sessionTerminationNoticeProvider), isNull);
    },
  );

  test(
    'five-minute boundary, rotation and repeat resume do not refresh early',
    () async {
      final rig = await _Rig.create(lifetime: const Duration(minutes: 6));
      await rig.presence.synchronizeNow();
      expect(rig.refreshCalls, 0);
      rig.now = rig.now.add(const Duration(minutes: 1));
      await rig.presence.synchronizeNow();
      expect(rig.refreshCalls, 1);
      await rig.presence.synchronizeNow();
      expect(rig.refreshCalls, 1);
      expect(rig.heartbeatTokens, [
        rig.original.accessToken,
        rig.renewed.accessToken,
        rig.renewed.accessToken,
      ]);
    },
  );

  for (final token in ['opaque', 'a.invalid.c', '', 'x' * 16385]) {
    test(
      'unknown expiry preserves session and uses normal heartbeat (${token.length})',
      () async {
        final rig = await _Rig.create(token: token);
        await rig.presence.synchronizeNow();
        expect(rig.refreshCalls, 0);
        expect(rig.heartbeatTokens, token.isEmpty ? isEmpty : [token]);
        expect(await rig.store.readSession(), isNotNull);
        expect(rig.container.read(sessionTerminationNoticeProvider), isNull);
      },
    );
  }

  test(
    'expiry hint without refresh credential does not sign out or refresh',
    () async {
      final rig = await _Rig.create(
        lifetime: const Duration(minutes: -1),
        withRefresh: false,
      );
      await rig.presence.synchronizeNow();
      expect(rig.refreshCalls, 0);
      expect(rig.heartbeatTokens, [rig.original.accessToken]);
      expect(await rig.store.readSession(), isNotNull);
    },
  );

  test(
    'already due restored session tries refresh, never local-expiry logout',
    () async {
      final rig = await _Rig.create(lifetime: const Duration(minutes: -1));
      await rig.presence.synchronizeNow();
      expect(rig.refreshCalls, 1);
      expect(rig.heartbeatTokens, [rig.renewed.accessToken]);
    },
  );

  for (final status in [400, 401]) {
    test(
      'rejected proactive $status retains valid session until a real 401',
      () async {
        final rig = await _Rig.create();
        rig.refreshFailure = status;
        await rig.presence.synchronizeNow();
        rig.now = rig.now.add(const Duration(minutes: 1));
        await rig.presence.synchronizeNow();
        expect(rig.refreshCalls, 1);
        expect(rig.heartbeatTokens, [
          rig.original.accessToken,
          rig.original.accessToken,
        ]);
        expect(rig.container.read(sessionTerminationNoticeProvider), isNull);
        expect(
          await rig.auth.handleSessionFailure(_failure(rig.original, 401)),
          isTrue,
        );
        expect(await rig.store.readSession(), isNull);
        expect(rig.refreshCalls, 2);
        expect(rig.container.read(sessionTerminationNoticeProvider), isNotNull);
      },
    );
  }

  for (final failure in ['network', '503']) {
    test(
      'temporary $failure preserves data and retries after cooldown',
      () async {
        final rig = await _Rig.create();
        rig.networkFailure = failure == 'network';
        rig.refreshFailure = failure == '503' ? 503 : null;
        await rig.presence.synchronizeNow();
        await rig.presence.synchronizeNow();
        rig.now = rig.now.add(const Duration(seconds: 29));
        await rig.presence.synchronizeNow();
        expect(rig.refreshCalls, 1);
        expect(await rig.store.readSession(), isNotNull);
        expect(rig.container.read(sessionTerminationNoticeProvider), isNull);
        rig.now = rig.now.add(const Duration(seconds: 1));
        rig.networkFailure = false;
        rig.refreshFailure = null;
        await rig.presence.synchronizeNow();
        expect(rig.refreshCalls, 2);
        expect(rig.heartbeatTokens.last, rig.renewed.accessToken);
      },
    );
  }

  test(
    'concurrent heartbeat, resume and 401 share one refresh rotation',
    () async {
      final rig = await _Rig.create();
      rig.entered = Completer<void>();
      rig.release = Completer<void>();
      final heartbeat = rig.presence.synchronizeNow();
      await rig.entered!.future;
      final resume = rig.auth.maintainSession();
      final failure = rig.auth.handleSessionFailure(
        _failure(rig.original, 401),
      );
      await Future<void>.delayed(Duration.zero);
      expect(rig.refreshCalls, 1);
      expect(rig.heartbeatTokens, isEmpty);
      rig.release!.complete();
      await Future.wait([heartbeat, resume, failure]);
      expect(rig.refreshCalls, 1);
      expect(rig.heartbeatTokens, [rig.renewed.accessToken]);
      expect(rig.container.read(sessionTerminationNoticeProvider), isNull);
    },
  );

  for (final action in ['logout', 'new-login', 'replaced', 'stop']) {
    test('in-flight proactive refresh respects $action', () async {
      final rig = await _Rig.create();
      rig.entered = Completer<void>();
      rig.release = Completer<void>();
      final pending = rig.presence.synchronizeNow();
      await rig.entered!.future;
      rig.presence.stop();
      if (action == 'logout') await rig.auth.logout();
      if (action == 'new-login') {
        await rig.store.saveSession(_session('fixture-other-login'));
      }
      if (action == 'replaced') {
        expect(
          await rig.auth.handleSessionFailure(
            _failure(rig.original, 409, code: 'session_replaced'),
          ),
          isTrue,
        );
      }
      rig.release!.complete();
      await pending;
      expect(rig.heartbeatTokens, isEmpty);
      expect((await rig.store.readSession())?.accessToken, switch (action) {
        'new-login' => 'fixture-other-login',
        'stop' => rig.renewed.accessToken,
        _ => null,
      });
    });
  }

  test(
    'claim parsing accepts only bounded numeric expiry and no other claims',
    () {
      String claims(Object body) =>
          'a.${base64Url.encode(utf8.encode(jsonEncode(body)))}.c';
      for (final expiry in [null, '1000', -1, 1.5, 100000000000, true, {}]) {
        expect(sessionRefreshDueAt(claims({'exp': expiry})), isNull);
      }
      expect(sessionRefreshDueAt(claims(['exp', 1000])), isNull);
      expect(sessionRefreshDueAt(claims({'nbf': 1000})), isNull);
      expect(
        sessionRefreshDueAt(claims({'exp': 1000, 'private': 'never logged'})),
        DateTime.fromMillisecondsSinceEpoch(700000, isUtc: true),
      );
    },
  );
}

DioException _failure(MobileSession session, int status, {String? code}) {
  final request = RequestOptions(
    path: '/api/client/heartbeat',
    headers: {
      'Authorization': 'Bearer ${session.accessToken}',
      'X-Device-Id': session.deviceId,
    },
  );
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: request,
      statusCode: status,
      data: code == null ? null : {'code': code},
    ),
  );
}

String _jwt(DateTime expires) =>
    'fixture.${base64Url.encode(utf8.encode(jsonEncode({'exp': expires.millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.signature';

MobileSession _session(String token) => MobileSession(
  accessToken: token,
  refreshToken: 'fixture-refresh',
  deviceId: 'fixture-device',
  installationId: 'fixture-install',
  userId: 'fixture-user',
  displayName: 'Fixture',
  username: 'fixture',
  policySignatureKey: '',
  imApiUrl: '',
  oaApiUrl: '',
);

class _Rig {
  _Rig();
  late SecureSessionStore store;
  late ProviderContainer container;
  late MobileSession original;
  late MobileSession renewed;
  late MobilePresenceCoordinator presence;
  int refreshCalls = 0;
  int? refreshFailure;
  bool networkFailure = false;
  Completer<void>? release;
  Completer<void>? entered;
  final heartbeatTokens = <String>[];
  final order = <String>[];
  DateTime now = DateTime.utc(2026, 9, 2, 12);
  AuthController get auth => container.read(authControllerProvider.notifier);

  static Future<_Rig> create({
    Duration lifetime = const Duration(minutes: 2),
    String? token,
    bool withRefresh = true,
  }) async {
    final rig = _Rig();
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    rig.store = SecureSessionStore();
    final originalToken = token ?? _jwt(rig.now.add(lifetime));
    rig.original = _session(originalToken).withTokens(
      accessToken: originalToken,
      refreshToken: withRefresh ? 'fixture-refresh' : '',
    );
    rig.renewed = _session(_jwt(rig.now.add(const Duration(hours: 2))))
        .withTokens(
          accessToken: _jwt(rig.now.add(const Duration(hours: 2))),
          refreshToken: 'fixture-renewed-refresh',
        );
    await rig.store.saveSession(rig.original);
    final refresh = Dio(BaseOptions(baseUrl: 'http://unused.invalid'));
    refresh.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) async {
          rig.refreshCalls++;
          rig.order.add('refresh');
          rig.entered?.complete();
          if (rig.release != null) await rig.release!.future;
          if (rig.refreshFailure != null || rig.networkFailure) {
            handler.reject(
              DioException(
                requestOptions: request,
                type: rig.networkFailure
                    ? DioExceptionType.connectionError
                    : DioExceptionType.badResponse,
                response: rig.networkFailure
                    ? null
                    : Response<Object?>(
                        requestOptions: request,
                        statusCode: rig.refreshFailure,
                        data: {'error': 'invalid_grant'},
                      ),
              ),
            );
          } else {
            handler.resolve(
              Response<Map<String, Object?>>(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'access_token': rig.renewed.accessToken,
                  'refresh_token': rig.renewed.refreshToken,
                },
              ),
            );
          }
        },
      ),
    );
    final api = Dio(BaseOptions(baseUrl: 'http://unused.invalid'));
    api.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.path == '/api/client/heartbeat') {
            rig.order.add('heartbeat');
            rig.heartbeatTokens.add(
              (request.headers['Authorization'] as String).substring(
                'Bearer '.length,
              ),
            );
          }
          handler.resolve(
            Response<Object?>(requestOptions: request, statusCode: 204),
          );
        },
      ),
    );
    rig.container = ProviderContainer(
      overrides: [
        sessionRefreshClockProvider.overrideWithValue(() => rig.now),
        secureSessionStoreProvider.overrideWithValue(rig.store),
        sessionRefreshClientProvider.overrideWithValue(refresh),
        dioProvider.overrideWithValue(api),
      ],
    );
    addTearDown(() {
      rig.container.dispose();
      refresh.close(force: true);
      api.close(force: true);
    });
    await rig.container.read(authControllerProvider.future);
    rig.presence = rig.container.read(mobilePresenceCoordinatorProvider);
    return rig;
  }
}

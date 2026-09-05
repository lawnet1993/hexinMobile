import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/api_client.dart';
import 'package:hexing_terminal_mobile/core/security/managed_security_repository.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final sameAccount in [false, true]) {
    test(
      'late command 401 preserves a newer ${sameAccount ? 'same' : 'different'} account session',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final store = SecureSessionStore();
        await store.saveSession(_session('old', 'account-a'));
        final container = ProviderContainer(
          overrides: [secureSessionStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        await container.read(authControllerProvider.future);
        final entered = Completer<void>();
        final release = Completer<void>();
        final dio = container.read(dioProvider);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              entered.complete();
              await release.future;
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<void>(
                    requestOptions: options,
                    statusCode: 401,
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );
        addTearDown(() => dio.close(force: true));
        final coordinator = container.read(
          managedTerminalCommandCoordinatorProvider,
        );
        final pending = coordinator.synchronizeNow();
        await entered.future;
        final newer = _session('new', sameAccount ? 'account-a' : 'account-b');
        await store.saveSession(newer);
        container.invalidate(authControllerProvider);
        await container.read(authControllerProvider.future);
        release.complete();
        await pending;
        expect((await store.readSession())?.accessToken, newer.accessToken);
        expect(
          container.read(authControllerProvider).value?.userId,
          newer.userId,
        );
        expect(container.read(sessionTerminationNoticeProvider), isNull);
      },
    );
  }
  group('request-bound session invalidation', () {
    late SecureSessionStore store;
    late ProviderContainer container;
    late AuthController auth;
    late MobileSession current;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      store = SecureSessionStore();
      current = _session('active', 'account-a');
      await store.saveSession(current);
      await store.savePushToken('fixture-push');
      await store.saveCredential('fixture-account', 'fixture-only');
      await store.saveDeviceId('fixture-installation');
      container = ProviderContainer(
        overrides: [secureSessionStoreProvider.overrideWithValue(store)],
      );
      await container.read(authControllerProvider.future);
      auth = container.read(authControllerProvider.notifier);
    });
    tearDown(() => container.dispose());

    test(
      'current 401 terminates once and preserves installation and credential',
      () async {
        final results = await Future.wait(
          List.generate(
            3,
            (_) => auth.handleSessionFailure(_failure(current, 401)),
          ),
        );
        expect(results.where((value) => value), hasLength(1));
        expect(await store.readSession(), isNull);
        expect(await store.readPushToken(), isNull);
        expect(await store.readCredential(), isNotNull);
        expect(await store.readDeviceId(), 'fixture-installation');
        expect(container.read(authControllerProvider).value, isNull);
        expect(
          container.read(sessionTerminationNoticeProvider),
          '登录已失效或已到期，请重新登录',
        );
      },
    );

    test(
      'current replacement invalidates but an old replacement cannot',
      () async {
        final old = _session('old', 'account-a');
        expect(
          await auth.handleSessionFailure(
            _failure(old, 409, code: 'session_replaced'),
          ),
          isFalse,
        );
        expect((await store.readSession())?.accessToken, current.accessToken);
        expect(
          await auth.handleSessionFailure(
            _failure(current, 409, code: 'session_replaced'),
          ),
          isTrue,
        );
        expect(await store.readSession(), isNull);
        expect(
          container.read(sessionTerminationNoticeProvider),
          '当前移动端已在另一台设备登录，请重新登录',
        );
      },
    );

    test('network failures, 5xx and unrelated 409 never terminate', () async {
      for (final status in [500, 503, 409]) {
        expect(
          await auth.handleSessionFailure(
            _failure(current, status, code: 'other'),
          ),
          isFalse,
        );
      }
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(
          await auth.handleSessionFailure(
            DioException(requestOptions: _request(current), type: type),
          ),
          isFalse,
        );
      }
      expect((await store.readSession())?.accessToken, current.accessToken);
      expect(await store.readPushToken(), 'fixture-push');
      expect(container.read(sessionTerminationNoticeProvider), isNull);
    });

    test(
      '401 without matching request device credentials is ignored',
      () async {
        final request = _request(current)
          ..headers['X-Device-Id'] = 'different-device';
        expect(
          await auth.handleSessionFailure(
            DioException(
              requestOptions: request,
              response: Response<void>(
                requestOptions: request,
                statusCode: 401,
              ),
            ),
          ),
          isFalse,
        );
        final anonymous = RequestOptions(path: '/api/client/commands');
        expect(
          await auth.handleSessionFailure(
            DioException(
              requestOptions: anonymous,
              response: Response<void>(
                requestOptions: anonymous,
                statusCode: 401,
              ),
            ),
          ),
          isFalse,
        );
        expect((await store.readSession())?.accessToken, current.accessToken);
      },
    );

    test('compare-and-clear rejects stale state and only clears its own push token', () async {
      final newer = _session('new', 'account-a');
      await store.saveSession(newer);
      expect(
        await store.clearSessionIfCurrent(current, clearCredential: true),
        isFalse,
      );
      expect(
        await store.replaceSessionIfCurrent(
          current,
          _session('late-refresh', 'account-a'),
        ),
        isFalse,
      );
      expect((await store.readSession())?.accessToken, newer.accessToken);
      expect(await store.readPushToken(), 'fixture-push');
      expect(await store.readCredential(), isNotNull);
      final reopened = SecureSessionStore();
      expect((await reopened.readSession())?.accessToken, newer.accessToken);
    });

    test(
      'pinned command credentials are not overwritten by interceptor',
      () async {
        final dio = container.read(dioProvider);
        RequestOptions? captured;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured = options;
              handler.resolve(
                Response<List<Object?>>(
                  requestOptions: options,
                  data: const [],
                  statusCode: 200,
                ),
              );
            },
          ),
        );
        addTearDown(() => dio.close(force: true));
        final old = _session('old', 'account-b');
        await container
            .read(managedSecurityRepositoryProvider)
            .fetchCommands(forSession: old);
        expect(requestUsedSession(captured!, old), isTrue);
        expect(requestUsedSession(captured!, current), isFalse);
      },
    );

    test('stopped coordinator ignores its in-flight 401', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final dio = container.read(dioProvider);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            entered.complete();
            await release.future;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<void>(
                  requestOptions: options,
                  statusCode: 401,
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );
      addTearDown(() => dio.close(force: true));
      final coordinator = container.read(
        managedTerminalCommandCoordinatorProvider,
      );
      final pending = coordinator.start();
      await entered.future;
      coordinator.stop();
      release.complete();
      await pending;
      expect((await store.readSession())?.accessToken, current.accessToken);
      expect(container.read(sessionTerminationNoticeProvider), isNull);
    });
  });

  for (final outcome in [
    'new-login',
    'logout',
    'success',
    'unavailable',
    'rejected',
  ]) {
    test('refresh completion is isolated: $outcome', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      final original = _session('original', 'account-a').withTokens(
        accessToken: 'fixture-original',
        refreshToken: 'fixture-refresh',
      );
      await store.saveSession(original);
      final entered = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final client = Dio(BaseOptions(baseUrl: 'http://unused.invalid'));
      client.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            calls++;
            entered.complete();
            await release.future;
            if (outcome == 'unavailable' || outcome == 'rejected') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response<void>(
                    requestOptions: options,
                    statusCode: outcome == 'unavailable' ? 503 : 401,
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            } else {
              handler.resolve(
                Response<Map<String, Object?>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'access_token': 'fixture-refreshed'},
                ),
              );
            }
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          secureSessionStoreProvider.overrideWithValue(store),
          sessionRefreshClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => client.close(force: true));
      await container.read(authControllerProvider.future);
      final auth = container.read(authControllerProvider.notifier);
      final pending = auth.handleSessionFailure(_failure(original, 401));
      await entered.future;
      Future<MobileSession?>? concurrent;
      if (outcome == 'new-login') {
        await store.saveSession(_session('new', 'account-b'));
        container.invalidate(authControllerProvider);
        await container.read(authControllerProvider.future);
      } else if (outcome == 'logout') {
        await auth.logout();
      } else if (outcome == 'success') {
        concurrent = auth.refreshSession();
      }
      release.complete();
      final terminated = await pending;
      if (concurrent != null) await concurrent;
      expect(calls, 1);
      final expected = switch (outcome) {
        'new-login' => 'fixture-new',
        'success' => 'fixture-refreshed',
        'unavailable' => 'fixture-original',
        _ => null,
      };
      expect((await store.readSession())?.accessToken, expected);
      expect(terminated, outcome == 'rejected');
      expect(
        container.read(sessionTerminationNoticeProvider),
        outcome == 'rejected' ? '登录已失效或已到期，请重新登录' : null,
      );
      expect((await SecureSessionStore().readSession())?.accessToken, expected);
    });
  }
}

RequestOptions _request(MobileSession session) => RequestOptions(
  path: '/api/client/commands',
  headers: {
    'Authorization': 'Bearer ${session.accessToken}',
    'X-Device-Id': session.deviceId,
  },
);

DioException _failure(MobileSession session, int status, {String? code}) {
  final request = _request(session);
  return DioException(
    requestOptions: request,
    response: Response<Object?>(
      requestOptions: request,
      statusCode: status,
      data: code == null ? null : {'code': code},
    ),
    type: DioExceptionType.badResponse,
  );
}

MobileSession _session(String token, String account) => MobileSession(
  accessToken: 'fixture-$token',
  deviceId: 'fixture-device',
  userId: account,
  displayName: account,
  username: account,
  policySignatureKey: '',
  imApiUrl: '',
  oaApiUrl: '',
);

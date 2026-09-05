import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final outcome in [
    'success',
    'invalid_grant',
    'invalid_client',
    'unknown',
    'network',
  ]) {
    test('safe refresh diagnostics: $outcome', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      const session = MobileSession(
        accessToken: 'private-access',
        refreshToken: 'private-refresh',
        deviceId: 'private-device',
        userId: 'private-account',
        displayName: 'private-name',
        username: 'private-username',
        policySignatureKey: '',
        imApiUrl: '',
        oaApiUrl: '',
      );
      await store.saveSession(session);
      final lines = <String>[];
      final originalPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) lines.add(message);
      };
      addTearDown(() => debugPrint = originalPrint);
      final dio = Dio(BaseOptions(baseUrl: 'http://unused.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (outcome == 'success') {
              handler.resolve(
                Response<Map<String, Object?>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'access_token': 'private-new-access',
                    'refresh_token': 'private-new-refresh',
                  },
                ),
              );
            } else {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: outcome == 'network'
                      ? DioExceptionType.connectionError
                      : DioExceptionType.badResponse,
                  response: outcome == 'network'
                      ? null
                      : Response<Map<String, Object?>>(
                          requestOptions: options,
                          statusCode: 400,
                          data: {
                            'error': outcome == 'unknown'
                                ? 'private-code'
                                : outcome,
                            'error_description': 'private-diagnostic',
                            'access_token': 'private-response',
                          },
                        ),
                ),
              );
            }
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [
          secureSessionStoreProvider.overrideWithValue(store),
          sessionRefreshClientProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => dio.close(force: true));
      await container.read(authControllerProvider.future);
      final operation = container
          .read(authControllerProvider.notifier)
          .refreshSession();
      if (outcome == 'network') {
        await expectLater(operation, throwsA(isA<DioException>()));
      } else {
        await operation;
      }
      final entries = lines
          .where((line) => line.startsWith('MOBILE_SESSION_REFRESH '))
          .toList();
      expect(entries, hasLength(1));
      expect(entries.single, isNot(contains('private')));
      final metadata = jsonDecode(
        entries.single.substring('MOBILE_SESSION_REFRESH '.length),
      ) as Map;
      expect(
        metadata['action'],
        outcome == 'success'
            ? 'accepted'
            : outcome == 'network'
            ? 'retry'
            : 'rejected',
      );
      expect(metadata['errorCode'], switch (outcome) {
        'invalid_grant' || 'invalid_client' => outcome,
        'unknown' => 'unrecognized',
        _ => null,
      });
      expect(
        (await store.readSession())?.accessToken,
        outcome == 'success' ? 'private-new-access' : 'private-access',
      );
    });
  }

  test(
    'refresh transport refuses redirects for credential-bearing requests',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(sessionRefreshClientProvider).options.followRedirects,
        false,
      );
    },
  );

  test('real HTTP 307 cannot receive a replayed refresh credential', () async {
    HttpOverrides.global = _RealHttp();
    addTearDown(() => HttpOverrides.global = null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var received = 0;
    var redirected = 0;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/refresh') {
        received++;
        request.response.statusCode = 307;
        request.response.headers.set(
          'Location',
          'http://127.0.0.1:${server.port}/unexpected',
        );
      } else {
        redirected++;
        request.response.statusCode = 200;
      }
      await request.response.close();
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final client = container.read(sessionRefreshClientProvider);
    await expectLater(
      client.post<Object?>(
        'http://127.0.0.1:${server.port}/refresh',
        data: {'grant_type': 'refresh_token', 'refresh_token': 'fixture-only'},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      ),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          307,
        ),
      ),
    );
    expect(received, 1);
    expect(redirected, 0);
  });
}

class _RealHttp extends HttpOverrides {}

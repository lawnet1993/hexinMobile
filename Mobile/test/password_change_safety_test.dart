import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/device/mobile_device_identity.dart';
import 'package:hexing_terminal_mobile/core/network/api_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/settings_pages.dart';

// Synthetic credentials only; no requests leave the interceptor below.
const _session = MobileSession(
  accessToken: 'fixture-session',
  deviceId: 'fixture-device',
  userId: 'fixture-user',
  displayName: 'Fixture',
  username: 'fixture-user',
  policySignatureKey: '',
  imApiUrl: '',
  oaApiUrl: '',
);
const _keys = [
  'current-password-field',
  'new-password-field',
  'confirm-password-field',
];
const _unknown = '修改结果尚未确认，请稍后核实，勿重复提交';

void main() {
  testWidgets('keyboard advances through password fields without suggestions', (
    tester,
  ) async {
    await _open(tester);
    final first = tester.widget<TextFormField>(
      find.byKey(const Key('current-password-field')),
    );
    final firstInput = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('current-password-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(first.enabled, isTrue);
    expect(firstInput.textInputAction, TextInputAction.next);
    expect(firstInput.autocorrect, isFalse);
    expect(firstInput.enableSuggestions, isFalse);
    await tester.tap(find.byKey(const Key('current-password-field')));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    final next = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('new-password-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(next.focusNode.hasFocus, isTrue);
  });

  testWidgets(
    'late server rejection after changing session shows no stale error',
    (tester) async {
      final pending = Completer<void>();
      final fixture = await _open(
        tester,
        onRequest: (options, handler) async {
          await pending.future;
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 400),
            ),
          );
        },
      );
      await _fill(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pump();
      (fixture.container.read(authControllerProvider.notifier) as _Auth)
          .replace(_session.withTokens(accessToken: 'other-fixture'));
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change-password-error')), findsNothing);
    },
  );

  testWidgets(
    'success removes only obsolete remembered password and keeps session',
    (tester) async {
      final fixture = await _open(tester);
      await fixture.store.saveCredential(_session.username, 'fixture-old');
      await _fill(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pumpAndSettle();
      expect(await fixture.store.readCredential(), isNull);
      expect(
        (await fixture.store.readSession())?.isSameSession(_session),
        isTrue,
      );
    },
  );

  testWidgets('change password pins the submitting account authorization', (
    tester,
  ) async {
    RequestOptions? sent;
    await _open(
      tester,
      onRequest: (options, handler) {
        sent = options;
        handler.resolve(
          Response<void>(requestOptions: options, statusCode: 204),
        );
      },
    );
    await _fill(tester);
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();
    expect(
      sent?.headers['Authorization'] == 'Bearer ${_session.accessToken}',
      isTrue,
    );
    expect(sent?.headers['X-Device-Id'] == _session.deviceId, isTrue);
  });

  for (final type in [
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.connectionError,
  ]) {
    testWidgets('$type cannot claim password was not changed', (tester) async {
      final fixture = await _open(
        tester,
        onRequest: (options, handler) {
          handler.reject(DioException(requestOptions: options, type: type));
        },
      );
      await _fill(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pumpAndSettle();
      expect(find.text(_unknown), findsOneWidget);
      expect(
        (await fixture.store.readSession())?.isSameSession(_session),
        isTrue,
      );
    });
  }

  testWidgets(
    '500 leaves password outcome unconfirmed without echoing response',
    (tester) async {
      await _open(
        tester,
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 500,
                data: {'message': 'unsafe-server-echo'},
              ),
            ),
          );
        },
      );
      await _fill(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pumpAndSettle();
      expect(find.text(_unknown), findsOneWidget);
      expect(find.textContaining('unsafe-server-echo'), findsNothing);
    },
  );

  testWidgets('busy password request cannot edit fields or dismiss the sheet', (
    tester,
  ) async {
    final pending = Completer<void>();
    await _open(
      tester,
      onRequest: (options, handler) async {
        await pending.future;
        handler.resolve(
          Response<void>(requestOptions: options, statusCode: 204),
        );
      },
    );
    await _fill(tester);
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pump();
    for (final key in _keys) {
      expect(
        tester.widget<TextFormField>(find.byKey(Key(key))).enabled,
        isFalse,
      );
    }
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('current-password-field')), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('密码已修改，其他设备需重新登录'), findsOneWidget);
  });

  testWidgets('matching confirmation clears validation error while editing', (
    tester,
  ) async {
    await _open(tester);
    await _fill(tester, confirm: 'fixture-mismatch');
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的新密码不一致'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'fixture-new',
    );
    await tester.pumpAndSettle();
    expect(find.text('两次输入的新密码不一致'), findsNothing);
  });

  testWidgets(
    'changed account ignores late success and preserves its saved password',
    (tester) async {
      final pending = Completer<void>();
      final fixture = await _open(
        tester,
        onRequest: (options, handler) async {
          await pending.future;
          handler.resolve(
            Response<void>(requestOptions: options, statusCode: 204),
          );
        },
      );
      await _fill(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pump();
      final replacement = _session.withTokens(
        accessToken: 'fixture-new-session',
      );
      await fixture.store.saveSession(replacement);
      await fixture.store.saveCredential(
        _session.username,
        'fixture-new-login',
      );
      (fixture.container.read(authControllerProvider.notifier) as _Auth)
          .replace(replacement);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('密码已修改，其他设备需重新登录'), findsNothing);
      expect(
        (await fixture.store.readCredential())?.password == 'fixture-new-login',
        isTrue,
      );
    },
  );
}

Future<void> _fill(
  WidgetTester tester, {
  String confirm = 'fixture-new',
}) async {
  for (final entry in {
    'current-password-field': 'fixture-old',
    'new-password-field': 'fixture-new',
    'confirm-password-field': confirm,
  }.entries) {
    await tester.enterText(find.byKey(Key(entry.key)), entry.value);
  }
  await tester.pump();
}

Future<({SecureSessionStore store, ProviderContainer container})> _open(
  WidgetTester tester, {
  void Function(RequestOptions, RequestInterceptorHandler)? onRequest,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  FlutterSecureStorage.setMockInitialValues({});
  final store = SecureSessionStore();
  await store.saveSession(_session);
  final dio = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest:
            onRequest ??
            (options, handler) {
              handler.resolve(
                Response<void>(requestOptions: options, statusCode: 204),
              );
            },
      ),
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        secureSessionStoreProvider.overrideWithValue(store),
        dioProvider.overrideWithValue(dio),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        imRealtimeAvailabilityProvider.overrideWithValue(
          ImRealtimeAvailability.available,
        ),
        accountSecurityDeviceIdentityProvider.overrideWith(
          (ref) async => const MobileDeviceIdentity(
            id: 'fixture-install',
            name: 'Fixture Android',
            fingerprint: 'fixture-fingerprint',
            operatingSystem: 'Android 16',
            clientVersion: '1.0.0',
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const AccountSecurityPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AccountSecurityPage)),
  );
  await tester.tap(find.byKey(const Key('open-change-password')));
  await tester.pumpAndSettle();
  return (store: store, container: container);
}

class _Auth extends AuthController {
  @override
  Future<MobileSession?> build() async => _session;
  void replace(MobileSession session) => state = AsyncData(session);
}

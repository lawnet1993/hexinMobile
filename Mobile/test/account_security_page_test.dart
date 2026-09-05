import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hexing_terminal_mobile/core/device/mobile_device_identity.dart';
import 'package:hexing_terminal_mobile/core/network/api_client.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/settings_pages.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final sample in [
    (online: null, fresh: true, expected: '已登录'),
    (online: true, fresh: false, expected: '已登录'),
    (online: false, fresh: false, expected: '已登录'),
    (online: true, fresh: true, expected: '已登录·在线'),
    (online: false, fresh: true, expected: '已登录·离线'),
  ]) {
    testWidgets(
      'account presence ${sample.online} fresh=${sample.fresh} stays truthful',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_TestAuthController.new),
              imBootstrapProvider.overrideWith(
                (ref) async => PreviewData.imBootstrap,
              ),
              imRealtimeAvailabilityProvider.overrideWithValue(
                ImRealtimeAvailability.available,
              ),
              imMemberPresenceProjectionProvider.overrideWith(
                () => _FixedAccountPresence(
                  ImMemberPresenceObservation(
                    online: sample.online,
                    fresh: sample.fresh,
                    order: 1,
                  ),
                ),
              ),
              accountSecurityDeviceIdentityProvider.overrideWith(
                (ref) async => const MobileDeviceIdentity(
                  id: 'fixture-device',
                  name: 'Test device',
                  fingerprint: 'fixture',
                  operatingSystem: 'Android 16',
                  clientVersion: '1.0.1',
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
        expect(find.text(sample.expected), findsOneWidget);
        if (!sample.fresh || sample.online == null) {
          expect(find.text('已登录·离线'), findsNothing);
          expect(find.text('已登录·在线'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('account status keeps connecting distinct from interrupted', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.connecting,
          ),
          accountSecurityDeviceIdentityProvider.overrideWith(
            (ref) async => const MobileDeviceIdentity(
              id: 'test-installation-id',
              name: 'Test device',
              fingerprint: 'test-fingerprint',
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

    expect(find.text('已登录·同步中'), findsOneWidget);
    expect(find.text('已登录·同步中断'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password form keeps compact independent visibility controls', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          accountSecurityDeviceIdentityProvider.overrideWith(
            (ref) async => const MobileDeviceIdentity(
              id: 'test-installation-id',
              name: 'Google sdk_gphone64_x86_64',
              fingerprint: 'test-fingerprint',
              operatingSystem: 'Android 16',
              clientVersion: '1.0.0',
            ),
          ),
          dioProvider.overrideWithValue(_offlineDio()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AccountSecurityPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前设备'), findsOneWidget);
    expect(find.text('设备 ID'), findsNothing);
    expect(find.text('Android 模拟器 · Android 16'), findsOneWidget);
    expect(find.text('已登录·同步中断'), findsOneWidget);
    expect(find.text('已验证·状态未知'), findsNothing);
    expect(find.byKey(const Key('current-password-field')), findsNothing);
    expect(find.byKey(const Key('open-change-password')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-change-password')));
    await tester.pumpAndSettle();

    expect(find.text('显示密码'), findsNothing);
    expect(find.byTooltip('显示当前密码'), findsOneWidget);
    expect(find.byTooltip('显示新密码'), findsOneWidget);
    expect(find.byTooltip('显示再次输入新密码'), findsOneWidget);
    expect(find.text('已登录·在线'), findsNothing);

    final submit = tester.getSize(
      find.byKey(const Key('change-password-submit')),
    );
    expect(submit, const Size(118, 36));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    for (final key in const [
      Key('current-password-field'),
      Key('new-password-field'),
      Key('confirm-password-field'),
    ]) {
      expect(tester.getSize(find.byKey(key)).height, lessThanOrEqualTo(40));
    }

    await tester.tap(find.byTooltip('显示当前密码'));
    await tester.pump();
    expect(find.byTooltip('隐藏当前密码'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('current-password-field')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isFalse,
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('new-password-field')),
              matching: find.byType(EditableText),
            ),
          )
          .obscureText,
      isTrue,
    );

    final content = tester.getSize(
      find.byKey(const Key('change-password-form-content')),
    );
    expect(content.height, lessThanOrEqualTo(280));

    await tester.enterText(
      find.byKey(const Key('current-password-field')),
      'invalid-current',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'new-password-123',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    expect(find.text('修改结果尚未确认，请稍后核实，勿重复提交'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('current-password-field')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'invalid-current',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful password change keeps the current session', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.available,
          ),
          accountSecurityDeviceIdentityProvider.overrideWith(
            (ref) async => const MobileDeviceIdentity(
              id: 'test-installation-id',
              name: 'Google sdk_gphone64_x86_64',
              fingerprint: 'test-fingerprint',
              operatingSystem: 'Android 16',
              clientVersion: '1.0.0',
            ),
          ),
          dioProvider.overrideWithValue(_successDio()),
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
    await tester.enterText(
      find.byKey(const Key('current-password-field')),
      'current-password',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'new-password-123',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('current-password-field')), findsNothing);
    expect(find.text('密码已修改，其他设备需重新登录'), findsOneWidget);
    expect(container.read(authControllerProvider).value, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

Dio _offlineDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      ),
    ),
  );
  return dio;
}

Dio _successDio() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response<void>(requestOptions: options, statusCode: 204),
      ),
    ),
  );
  return dio;
}

final class _TestAuthController extends AuthController {
  @override
  Future<MobileSession?> build() async => const MobileSession(
    accessToken: 'test-token',
    deviceId: 'd091b9aa00000000afc3f8',
    userId: 'preview-user',
    displayName: 'Codex 测试终端',
    username: 'codex_test_20260824',
    policySignatureKey: 'test-key',
    imApiUrl: 'https://im.invalid',
    oaApiUrl: 'https://oa.invalid',
  );
}

class _FixedAccountPresence extends ImMemberPresenceProjection {
  _FixedAccountPresence(this.observation);
  final ImMemberPresenceObservation observation;
  @override
  Map<String, ImMemberPresenceObservation> build() => {
    PreviewData.imBootstrap.currentMember.id: observation,
  };
}

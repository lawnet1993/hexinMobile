import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/auth/presentation/login_page.dart';

void main() {
  testWidgets('会话退出原因持续显示且不重复弹提示', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_RememberedAuthController.new),
      ],
    );
    addTearDown(container.dispose);
    final notices = container.read(sessionTerminationNoticeProvider.notifier);
    notices.showOnce('当前移动端已在另一台设备登录，请重新登录');
    notices.showOnce('登录已失效或已到期，请重新登录');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    expect(find.byKey(const Key('login-session-notice')), findsOneWidget);
    expect(find.text('当前移动端已在另一台设备登录，请重新登录'), findsOneWidget);
    expect(find.text('登录已失效或已到期，请重新登录'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(container.read(sessionTerminationNoticeProvider), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重新提交登录时清除旧会话提示而不暴露记住密码', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_RememberedAuthController.new),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sessionTerminationNoticeProvider.notifier)
        .showOnce('登录已失效或已到期，请重新登录');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, '登录');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-session-notice')), findsNothing);
    expect(find.text('not-rendered-test-password'), findsNothing);
    expect(
      (container.read(
        authControllerProvider.notifier,
      ) as _RememberedAuthController).submittedPassword,
      'not-rendered-test-password',
    );
  });

  testWidgets('记住的密码不回填到输入框', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_RememberedAuthController.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields.first.controller?.text, 'uat-user');
    expect(fields.last.controller?.text, isEmpty);
    expect(fields.last.decoration?.hintText, '已保存密码');
    expect(find.text('not-rendered-test-password'), findsNothing);
    expect(find.byTooltip('已安全保存'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    final controller = container.read(
      authControllerProvider.notifier,
    ) as _RememberedAuthController;
    expect(controller.submittedPassword, 'not-rendered-test-password');

    await tester.tap(find.text('忘记密码'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-message-sheet')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('失效的记住密码在 401 后清除', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _RememberedAuthController(failLogin: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    final controller = container.read(
      authControllerProvider.notifier,
    ) as _RememberedAuthController;
    expect(controller.credentialCleared, isTrue);
    final passwordField = tester
        .widgetList<TextField>(find.byType(TextField))
        .last;
    expect(passwordField.controller?.text, isEmpty);
    expect(passwordField.decoration?.hintText, '请输入密码');
  });
}

final class _RememberedAuthController extends AuthController {
  _RememberedAuthController({this.failLogin = false});

  final bool failLogin;
  String submittedPassword = '';
  bool credentialCleared = false;

  @override
  Future<MobileSession?> build() async => null;

  @override
  Future<SavedCredential?> savedCredential() async =>
      const SavedCredential('uat-user', 'not-rendered-test-password');

  @override
  Future<void> login({
    required String username,
    required String password,
    required bool remember,
  }) async {
    submittedPassword = password;
    state = failLogin
        ? const AsyncError(LoginFailure('账号或密码错误'), StackTrace.empty)
        : const AsyncData(null);
  }

  @override
  Future<void> clearSavedCredential() async {
    credentialCleared = true;
  }
}

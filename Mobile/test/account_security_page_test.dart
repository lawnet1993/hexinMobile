import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/settings_pages.dart';

void main() {
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
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AccountSecurityPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('显示密码'), findsNothing);
    expect(find.byTooltip('显示当前密码'), findsOneWidget);
    expect(find.byTooltip('显示新密码'), findsOneWidget);
    expect(find.byTooltip('显示再次输入新密码'), findsOneWidget);

    final submit = tester.getSize(
      find.byKey(const Key('change-password-submit')),
    );
    expect(submit, const Size(132, 40));

    for (final key in const [
      Key('current-password-field'),
      Key('new-password-field'),
      Key('confirm-password-field'),
    ]) {
      expect(tester.getSize(find.byKey(key)).height, lessThanOrEqualTo(48));
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
    expect(content.height, lessThanOrEqualTo(240));
    expect(tester.takeException(), isNull);
  });
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

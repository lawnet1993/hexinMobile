import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/settings_pages.dart';

void main() {
  testWidgets('help page uses current names and a compact diagnostics row', (
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
        child: MaterialApp(
          theme: AppTheme.light,
          home: const HelpFeedbackPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('反馈与诊断'), findsOneWidget);
    expect(find.text('诊断信息'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('复制诊断信息'), findsNothing);

    await tester.tap(find.text('无法收到消息提醒'));
    await tester.pumpAndSettle();
    expect(find.text('请确认系统通知权限已开启，并在“通知设置”中启用对应提醒。'), findsOneWidget);
    expect(find.textContaining('“消息通知”'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('copy-diagnostics-entry'))).height,
      lessThanOrEqualTo(50),
    );
    expect(tester.takeException(), isNull);
  });
}

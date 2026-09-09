import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/network_security_page.dart';

void main() {
  testWidgets('network security is a compact desktop-only reminder', (
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
      MaterialApp(theme: AppTheme.light, home: const NetworkSecurityPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('安全连接由桌面端管理'), findsOneWidget);
    expect(find.textContaining('消息与审批直接同步'), findsOneWidget);
    expect(find.textContaining('站点隧道'), findsOneWidget);
    expect(find.text('重新检测'), findsNothing);
    expect(find.text('上传 / 下载'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

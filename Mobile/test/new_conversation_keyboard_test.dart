import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';

void main() {
  for (final config in [
    (size: const Size(390, 844), keyboard: 340.0, scale: 1.0),
    (size: const Size(320, 568), keyboard: 260.0, scale: 1.0),
    (size: const Size(390, 844), keyboard: 340.0, scale: 1.3),
  ]) {
    testWidgets(
      'group create remains above keyboard ${config.size} text ${config.scale}',
      (tester) async {
        tester.view.physicalSize = config.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              imBootstrapProvider.overrideWith(
                (_) async => PreviewData.imBootstrap,
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.scale)),
                child: child!,
              ),
              home: const MessagesPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('发起会话'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedButton<bool>),
            matching: find.text('群聊'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Checkbox).first);
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.hintText == '群名称',
          ),
          'AI-UAT-keyboard-group',
        );
        tester.view.viewInsets = FakeViewPadding(bottom: config.keyboard);
        await tester.pumpAndSettle();
        final submit = find.widgetWithText(FilledButton, '创建群聊（1）');
        expect(tester.takeException(), isNull);
        expect(
          tester.getBottomRight(submit).dy,
          lessThanOrEqualTo(config.size.height - config.keyboard),
        );
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        expect(find.text('AI-UAT-keyboard-group'), findsOneWidget);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.text('创建群聊（1）'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

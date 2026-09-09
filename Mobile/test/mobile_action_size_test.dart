import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  testWidgets('search field exposes its purpose without changing visual label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MobileSearchField(hintText: '搜索联系人、群组或消息'),
        ),
      ),
    );

    expect(find.bySemanticsLabel('搜索联系人、群组或消息'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('search semantics also supports a route-owned controller', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = MobileSearchTextController(searchLabel: '搜索成员');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileSearchField(
            hintText: '搜索成员',
            controller: controller,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('搜索成员'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '林川');
    expect(controller.text, '林川');
    semantics.dispose();
  });

  for (final kind in ['filled', 'outlined', 'text']) {
    testWidgets('$kind action keeps a compact mobile surface', (
      tester,
    ) async {
      var taps = 0;
      void onPressed() => taps++;
      const label = Text('确定');
      final button = switch (kind) {
        'filled' => FilledButton(
          style: compactMobileActionStyle,
          onPressed: onPressed,
          child: label,
        ),
        'outlined' => OutlinedButton(
          style: compactMobileActionStyle,
          onPressed: onPressed,
          child: label,
        ),
        _ => TextButton(
          style: compactMobileActionStyle,
          onPressed: onPressed,
          child: label,
        ),
      };
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: button)),
      ));
      final control = find.byWidget(button);
      final surface = find.descendant(
        of: control, matching: find.byType(Material),
      );
      expect(tester.getSize(surface).height, 34);
      expect(tester.getSize(control).height, 34);
      expect(tester.getSize(control).width, 64);
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

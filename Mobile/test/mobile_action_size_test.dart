import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  for (final kind in ['filled', 'outlined', 'text']) {
    testWidgets('$kind action keeps a compact surface and padded touch target', (
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
      expect(tester.getSize(control).height, 48);
      expect(tester.getSize(control).width, 64);
      // The transparent padding still receives the tap.
      await tester.tapAt(tester.getTopLeft(control) + const Offset(32, 2));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

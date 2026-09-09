import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/shared/widgets/app_version_label.dart';

void main() {
  testWidgets(
    'renders the installed package version instead of a UI constant',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appVersionProvider.overrideWith((ref) async => '2.7.13')],
          child: const MaterialApp(home: Scaffold(body: AppVersionLabel())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('v2.7.13'), findsOneWidget);
      expect(find.text('v1.0.1'), findsNothing);
    },
  );
}

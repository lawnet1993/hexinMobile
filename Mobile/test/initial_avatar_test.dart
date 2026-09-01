import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  testWidgets('preset avatar keys render the desktop-compatible portrait', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InitialAvatar(name: '测试成员', avatarKey: 'person'),
        ),
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown avatar keys keep the initials fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InitialAvatar(name: '测试成员', avatarKey: 'unknown'),
        ),
      ),
    );

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isNull);
    expect(find.text('测'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

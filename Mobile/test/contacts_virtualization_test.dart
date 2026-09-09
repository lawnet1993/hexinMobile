import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  testWidgets('an expanded 2000 member department only mounts visible rows', (
    tester,
  ) async {
    await _open(tester);
    final search = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('contacts-search-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(search.decoration?.hintText, '搜索姓名或部门');
    expect(
      tester
          .getSize(find.byKey(const Key('organization-department-selector')))
          .height,
      greaterThanOrEqualTo(40),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('directory-mode-组织'))).height,
      greaterThanOrEqualTo(40),
    );
    expect(find.byType(InitialAvatar), findsNothing);
    await tester.tap(find.byKey(const Key('department-group-a')));
    await tester.pumpAndSettle();
    expect(find.byType(InitialAvatar).evaluate().length, lessThan(22));
    debugPrint(
      'CONTACT-VIRTUAL-UAT initial-mounted=${find.byType(InitialAvatar).evaluate().length} dataset=2000',
    );
    expect(find.text('Member 0'), findsOneWidget);
    expect(find.text('Member 1999'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling far into a department does not retain all previous rows',
    (tester) async {
      await _open(tester);
      await tester.tap(find.byKey(const Key('department-group-a')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 7; i++) {
        await tester.drag(
          find.byKey(const Key('contacts-page-scroll')),
          const Offset(0, -1600),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(InitialAvatar).evaluate().length, lessThan(28));
      debugPrint(
        'CONTACT-VIRTUAL-UAT after-seven-scrolls-mounted=${find.byType(InitialAvatar).evaluate().length} dataset=2000',
      );
      expect(find.text('Member 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all 65 members can be reached naturally without paging button', (
    tester,
  ) async {
    await _open(tester, count: 65);
    await tester.tap(find.byKey(const Key('department-group-a')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Member 64'),
      320,
      scrollable: find.descendant(
        of: find.byKey(const Key('contacts-page-scroll')),
        matching: find.byType(Scrollable),
      ),
      maxScrolls: 25,
    );
    await tester.pumpAndSettle();
    expect(find.text('Member 64'), findsOneWidget);
    expect(find.textContaining('加载更多'), findsNothing);
    expect(find.byType(InitialAvatar).evaluate().length, lessThan(28));
  });

  testWidgets('many collapsed sibling departments are also virtualized', (
    tester,
  ) async {
    await _open(tester, count: 10, siblings: 1000);
    expect(find.byType(ExpansionTile).evaluate().length, lessThan(24));
    expect(find.byType(InitialAvatar), findsNothing);
  });

  testWidgets('search finds a member beyond the former department window', (
    tester,
  ) async {
    await _open(tester);
    final search = find.descendant(
      of: find.byKey(const Key('contacts-search-field')),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'fixture-1999');
    await tester.pumpAndSettle();
    expect(find.text('Member 1999'), findsOneWidget);
    expect(find.byType(InitialAvatar), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.byType(InitialAvatar), findsNothing);
  });

  testWidgets(
    'scroll back preserves department expansion and original member',
    (tester) async {
      await _open(tester, count: 100);
      await tester.tap(find.byKey(const Key('department-group-a')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('contacts-page-scroll')),
        const Offset(0, -2500),
      );
      await tester.pumpAndSettle();
      expect(find.text('Member 0'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('department-group-a')),
        -400,
        scrollable: find.descendant(
          of: find.byKey(const Key('contacts-page-scroll')),
          matching: find.byType(Scrollable),
        ),
        maxScrolls: 20,
      );
      await tester.pumpAndSettle();
      expect(find.text('Member 0'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('department-toggle-a-true')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ExpansionTile>(find.byType(ExpansionTile).first)
            .initiallyExpanded,
        isTrue,
      );
    },
  );

  testWidgets('empty departments remain visible without fake member rows', (
    tester,
  ) async {
    await _open(tester, count: 3, siblings: 1);
    expect(find.text('Sibling 0'), findsOneWidget);
    final header = tester.widget<ExpansionTile>(
      find.descendant(
        of: find.byKey(const Key('department-group-sibling-0')),
        matching: find.byType(ExpansionTile),
      ),
    );
    expect(header.showTrailingIcon, isFalse);
    expect(find.byType(InitialAvatar), findsNothing);
  });

  testWidgets(
    'collapse and reexpand keeps rows selectable with no duplicate members',
    (tester) async {
      await _open(tester, count: 12);
      final header = find.descendant(
        of: find.byKey(const Key('department-group-a')),
        matching: find.text('Department A'),
      );
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.text('Member 0'), findsOneWidget);
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.byType(InitialAvatar), findsNothing);
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(find.text('Member 0'), findsOneWidget);
    },
  );
}

Future<void> _open(
  WidgetTester tester, {
  int count = 2000,
  int siblings = 0,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final members = List.generate(
    count,
    (index) => ImMember(
      id: 'member-$index',
      username: 'fixture-$index',
      displayName: 'Member $index',
      isOnline: false,
      departmentId: 'a',
      departmentName: 'Department A',
      canStartDirect: true,
    ),
  );
  final departments = [
    const ImDepartment(
      id: 'a',
      name: 'Department A',
      code: 'A',
      parentId: '',
      sortOrder: 0,
    ),
    for (var i = 0; i < siblings; i++)
      ImDepartment(
        id: 'sibling-$i',
        name: 'Sibling $i',
        code: 'S$i',
        parentId: '',
        sortOrder: i + 1,
      ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contactPresenceRefresherProvider.overrideWithValue(() async {}),
        imBootstrapProvider.overrideWith(
          (_) async => ImBootstrap(
            currentMember: members.first,
            contacts: members.skip(1).toList(),
            conversations: const [],
          ),
        ),
        imDepartmentsProvider.overrideWith((_) async => departments),
        pendingFriendApplicationsProvider.overrideWith((_) async => const []),
      ],
      child: const MaterialApp(home: ContactsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

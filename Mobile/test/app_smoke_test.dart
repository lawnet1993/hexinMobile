import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';
import 'package:hexing_terminal_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:hexing_terminal_mobile/features/workbench/domain/app_catalog.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/all_apps_page.dart';

void main() {
  test('security shortcuts keep desktop-aligned destinations distinct', () {
    final loginDevices = MobileAppCatalog.entries.singleWhere(
      (item) => item.title == '登录设备',
    );
    final networkDiagnostics = MobileAppCatalog.entries.singleWhere(
      (item) => item.title == '网络诊断',
    );

    expect(loginDevices.route, '/login-devices');
    expect(networkDiagnostics.route, '/network-security');
  });

  testWidgets('bottom navigation has five ordered primary destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MobileBottomNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    final destinations = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((item) => item.label)
        .toList();
    expect(destinations, ['工作台', '消息', '待办', '通讯录', '我的']);
  });

  testWidgets('bottom navigation shows real message and contact badges', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MobileBottomNavigationBar(
            selectedIndex: 0,
            unreadCount: 7,
            pendingApprovalCount: 5,
            pendingFriendRequestCount: 3,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('消息'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('通讯录'), findsOneWidget);
    expect(find.text('7'), findsWidgets);
    expect(find.text('5'), findsWidgets);
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('friend-request route opens the new-friends mode directly', (
    tester,
  ) async {
    final mode = ValueNotifier<int>(0);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: mode,
            builder: (context, value, _) => ContactsPage(initialMode: value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无新的好友申请'), findsNothing);
    mode.value = 2;
    await tester.pumpAndSettle();

    expect(find.text('新朋友'), findsOneWidget);
    expect(find.text('暂无新的好友申请'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'organization directory includes self and filters by real department tree',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imBootstrapProvider.overrideWith(
              (ref) async => PreviewData.imBootstrap,
            ),
            imDepartmentsProvider.overrideWith(
              (ref) async => PreviewData.imDepartments,
            ),
            pendingFriendApplicationsProvider.overrideWith(
              (ref) async => const [],
            ),
          ],
          child: const MaterialApp(home: ContactsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('林晨'), findsOneWidget);
      expect(find.text('我'), findsOneWidget);
      expect(find.byTooltip('发送消息'), findsNWidgets(3));
      expect(find.byTooltip('联系人操作'), findsNothing);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);

      await tester.tap(
        find.byKey(const Key('organization-department-selector')),
      );
      await tester.pumpAndSettle();
      expect(find.text('选择部门'), findsOneWidget);

      await tester.tap(find.text('深圳运营部').last);
      await tester.pumpAndSettle();

      expect(find.text('冯逸'), findsOneWidget);
      expect(find.text('林晨'), findsNothing);
      expect(find.text('叶青'), findsNothing);
      expect(find.text('唐泽'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('organization directory renders the server member avatar', (
    tester,
  ) async {
    final source = PreviewData.imBootstrap;
    final current = source.currentMember;
    final bootstrap = ImBootstrap(
      currentMember: ImMember(
        id: current.id,
        username: current.username,
        displayName: current.displayName,
        isOnline: current.isOnline,
        avatarKey: 'custom',
        avatarDataUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        departmentId: current.departmentId,
        departmentName: current.departmentName,
      ),
      conversations: source.conversations,
      contacts: source.contacts,
      permissions: source.permissions,
      config: source.config,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith((ref) async => bootstrap),
          imDepartmentsProvider.overrideWith(
            (ref) async => PreviewData.imDepartments,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: const MaterialApp(home: ContactsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar));
    expect(
      avatars.where((avatar) => avatar.foregroundImage is MemoryImage),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('friends mode stays separate and exposes friend-only actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: const MaterialApp(home: ContactsPage(initialMode: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('冯逸'), findsOneWidget);
    expect(find.text('唐泽'), findsOneWidget);
    expect(find.text('叶青'), findsNothing);
    expect(find.byTooltip('联系人操作'), findsNWidgets(2));
    await tester.tap(find.byTooltip('联系人操作').first);
    await tester.pumpAndSettle();
    expect(find.text('发消息'), findsOneWidget);
    expect(find.text('修改备注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group directory stays separate from direct contacts', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: const MaterialApp(home: ContactsPage(initialMode: 3)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('华南运营协作'), findsOneWidget);
    expect(find.text('数据对接项目组'), findsOneWidget);
    expect(find.text('唐泽'), findsNothing);
    expect(find.text('冯逸'), findsNothing);
    expect(find.byIcon(Icons.groups_rounded), findsNWidgets(2));
  });

  testWidgets('offline contacts show the backend last-seen date', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: const MaterialApp(home: ContactsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('最近上线 08-13'), findsOneWidget);
  });

  testWidgets(
    'an app shortcut pushes a detail route and back returns to apps',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/apps',
        routes: [
          GoRoute(path: '/apps', builder: (_, _) => const AllAppsPage()),
          GoRoute(
            path: '/schedule',
            builder: (_, _) => const Scaffold(body: Text('真实日程页')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      final attendanceSection = find.byKey(const ValueKey('app-category-考勤'));
      expect(attendanceSection, findsOneWidget);
      expect(tester.getSize(attendanceSection).height, lessThanOrEqualTo(84));
      expect(find.text('我的常用'), findsNothing);
      expect(find.text('请假申请'), findsOneWidget);
      expect(find.text('报销申请'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const Key('all-app-icon-attendance.leave')))
            .height,
        32,
      );

      await tester.tap(find.text('日程').first);
      await tester.pumpAndSettle();
      expect(find.text('真实日程页'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('全部应用'), findsOneWidget);
    },
  );

  testWidgets(
    'all-app search filters the compact catalog without stale shortcuts',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
          ],
          child: const MaterialApp(home: AllAppsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '网络');
      await tester.pumpAndSettle();
      expect(find.text('网络诊断'), findsOneWidget);
      expect(find.text('我的常用'), findsNothing);
      expect(find.text('请假'), findsNothing);

      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('暂无匹配应用'), findsOneWidget);
    },
  );
}

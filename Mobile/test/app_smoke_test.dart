import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';
import 'package:hexing_terminal_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:hexing_terminal_mobile/features/workbench/data/managed_sites_repository.dart';
import 'package:hexing_terminal_mobile/features/workbench/domain/app_catalog.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/all_apps_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

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
      final flatContent = tester.widget<Material>(
        find.byKey(const Key('contacts-flat-content')),
      );
      expect(flatContent.type, MaterialType.transparency);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final pageContext = tester.element(find.byType(ContactsPage));
      expect(
        scaffold.backgroundColor,
        Theme.of(pageContext).colorScheme.surface,
      );
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
    'all apps preserves the server workbench order and application routes',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/apps',
        routes: [
          GoRoute(path: '/apps', builder: (_, _) => const AllAppsPage()),
          GoRoute(
            path: '/apply/:applicationKey',
            builder: (_, _) => const Scaffold(body: Text('真实申请页')),
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

      expect(find.text('考勤'), findsNothing);
      expect(find.text('费用'), findsNothing);
      expect(find.text('我的常用'), findsNothing);
      expect(find.text('请假申请'), findsOneWidget);
      expect(find.text('报销申请'), findsOneWidget);
      expect(find.text('日程'), findsNothing);
      expect(find.text('网络诊断'), findsNothing);
      final leaveLabel = tester.widget<Text>(find.text('请假申请'));
      expect(leaveLabel.maxLines, 2);
      expect(leaveLabel.textAlign, TextAlign.center);
      expect(
        tester
            .getSize(find.byKey(const Key('all-app-icon-attendance.leave')))
            .height,
        32,
      );

      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((item) => item.data)
          .whereType<String>()
          .toList();
      expect(labels.indexOf('请假申请'), lessThan(labels.indexOf('报销申请')));

      await tester.tap(find.text('请假申请'));
      await tester.pumpAndSettle();
      expect(find.text('真实申请页'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('全部应用'), findsOneWidget);
    },
  );

  testWidgets(
    'workbench and all apps share the exact server application names',
    (tester) async {
      const catalog = OaApplicationCatalog(
        catalogVersion: 'alignment-test',
        items: [
          OaApplicationCatalogItem(
            applicationKey: 'purchase.request',
            name: '采购申请',
            category: '采购',
            iconKey: 'purchase',
            iconDataUrl: null,
            displayOrder: 10,
            configurationKind: 'approval',
            configurationId: 'purchase-config',
            approvalTemplateId: 'purchase-template',
            allowOfflineDraft: true,
            availabilitySource: 'department',
            sourceDepartmentId: 'department-1',
          ),
          OaApplicationCatalogItem(
            applicationKey: 'seal.request',
            name: '用印申请',
            category: '行政',
            iconKey: 'seal',
            iconDataUrl: null,
            displayOrder: 20,
            configurationKind: 'approval',
            configurationId: 'seal-config',
            approvalTemplateId: 'seal-template',
            allowOfflineDraft: true,
            availabilitySource: 'department',
            sourceDepartmentId: 'department-1',
          ),
        ],
      );
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const WorkbenchPage()),
          GoRoute(path: '/apps', builder: (_, _) => const AllAppsPage()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith(
              (ref) async => PreviewData.oaBootstrap,
            ),
            oaApplicationCatalogProvider.overrideWith((ref) async => catalog),
            managedSitesProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('采购申请'), findsOneWidget);
      expect(find.text('用印申请'), findsOneWidget);
      expect(find.text('采购'), findsNothing);
      expect(find.text('用印'), findsNothing);

      await tester.tap(find.text('全部应用'));
      await tester.pumpAndSettle();
      expect(find.text('采购申请'), findsOneWidget);
      expect(find.text('用印申请'), findsOneWidget);
    },
  );

  testWidgets(
    'workbench renders only the latest announcement as a compact row',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith(
              (ref) async => PreviewData.oaBootstrap,
            ),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
          ],
          child: const MaterialApp(home: WorkbenchPage()),
        ),
      );
      await tester.pumpAndSettle();

      final announcementRow = find.ancestor(
        of: find.text('安全提示'),
        matching: find.byType(ListTile),
      );
      expect(announcementRow, findsOneWidget);
      expect(tester.getSize(announcementRow).height, lessThanOrEqualTo(48));
      expect(
        tester.getTopLeft(find.text('安全提示')).dy,
        lessThan(tester.getTopLeft(find.text('常用应用')).dy),
      );
      expect(
        tester.getTopLeft(find.text('安全提示')).dy,
        lessThan(tester.getTopLeft(find.textContaining('待我处理').first).dy),
      );
      expect(find.text('请及时完成本周终端安全检查'), findsNothing);
      expect(find.text('公告'), findsNothing);
      expect(find.text('暂无公告'), findsNothing);
    },
  );

  testWidgets(
    'workbench omits sites, stale schedules and the empty announcement surface',
    (tester) async {
      final source = PreviewData.oaBootstrap;
      final withoutAnnouncements = OaBootstrap(
        currentMemberId: source.currentMemberId,
        displayName: source.displayName,
        todos: source.todos,
        announcements: const [],
        templates: source.templates,
        approvalRequests: source.approvalRequests,
        approvalRequestsNextCursor: source.approvalRequestsNextCursor,
        approvalRequestsHasMore: source.approvalRequestsHasMore,
        notifications: source.notifications,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith(
              (ref) async => withoutAnnouncements,
            ),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
            mobileClockProvider.overrideWithValue(DateTime(2026, 8, 31)),
          ],
          child: const MaterialApp(home: WorkbenchPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('常用站点'), findsNothing);
      expect(find.text('今日日程'), findsNothing);
      expect(find.text('今天暂无日程'), findsNothing);
      expect(find.text('暂无公告'), findsNothing);
      expect(find.text('公告'), findsNothing);
    },
  );

  testWidgets('all-app search filters only the server workbench catalog', (
    tester,
  ) async {
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

    await tester.enterText(find.byType(TextField), '报销');
    await tester.pumpAndSettle();
    expect(find.text('报销申请'), findsOneWidget);
    expect(find.text('我的常用'), findsNothing);
    expect(find.text('请假申请'), findsNothing);
    expect(find.text('网络诊断'), findsNothing);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('暂无匹配应用'), findsOneWidget);
  });
}

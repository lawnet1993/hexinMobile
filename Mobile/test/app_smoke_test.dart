import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'support/fixture_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';
import 'package:hexing_terminal_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:hexing_terminal_mobile/features/workbench/data/managed_sites_repository.dart';
import 'package:hexing_terminal_mobile/features/workbench/domain/app_catalog.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/all_apps_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

void main() {
  test('existing direct conversation is reused only when unambiguous', () {
    const peer = ImMember(
      id: 'peer-1',
      username: 'peer.account',
      displayName: '测试成员',
      isOnline: false,
    );
    final source = PreviewData.imBootstrap;
    final conversation = ImConversation(
      id: 'direct-peer-1',
      type: 'direct',
      title: '${source.currentMember.displayName}、测试成员',
      preview: '',
      updatedAt: DateTime(2026, 9, 1),
      unreadCount: 0,
    );
    final bootstrap = ImBootstrap(
      currentMember: source.currentMember,
      conversations: [conversation],
      contacts: const [peer],
    );

    expect(
      existingDirectConversationForMember(bootstrap, peer)?.id,
      conversation.id,
    );

    final ambiguous = ImBootstrap(
      currentMember: source.currentMember,
      conversations: [
        conversation,
        ImConversation(
          id: 'direct-peer-duplicate',
          type: 'direct',
          title: '测试成员',
          preview: '',
          updatedAt: DateTime(2026, 9, 1),
          unreadCount: 0,
        ),
      ],
      contacts: const [peer],
    );
    expect(existingDirectConversationForMember(ambiguous, peer), isNull);
  });

  testWidgets('contact search dismisses the keyboard before opening chat', (
    tester,
  ) async {
    const peer = ImMember(
      id: 'peer-search',
      username: 'peer.search',
      displayName: '搜索成员',
      isOnline: false,
      departmentId: 'department-search',
      departmentName: '搜索部门',
      canStartDirect: true,
    );
    final source = PreviewData.imBootstrap;
    final conversation = ImConversation(
      id: 'direct-search',
      type: 'direct',
      title: '搜索成员',
      preview: '',
      updatedAt: DateTime(2026, 9, 1),
      unreadCount: 0,
    );
    final bootstrap = ImBootstrap(
      currentMember: source.currentMember,
      conversations: [conversation],
      contacts: const [peer],
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const ContactsPage()),
        GoRoute(
          path: '/chat/:id',
          builder: (_, state) =>
              Scaffold(body: Text('chat:${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactPresenceRefresherProvider.overrideWithValue(() async {}),
          imBootstrapProvider.overrideWith((ref) async => bootstrap),
          imDepartmentsProvider.overrideWith(
            (ref) async => const [
              ImDepartment(
                id: 'department-search',
                name: '搜索部门',
                code: 'SEARCH',
                parentId: '',
                sortOrder: 0,
              ),
            ],
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.descendant(
      of: find.byKey(const Key('contacts-search-field')),
      matching: find.byType(TextField),
    );
    await tester.showKeyboard(searchField);
    await tester.enterText(searchField, '搜索成员');
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('搜索成员').last);
    await tester.pumpAndSettle();

    expect(find.text('chat:direct-search'), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

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
            pendingWorkCount: 5,
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

  test('bottom navigation pending badge includes todos and approvals', () {
    expect(mobilePendingWorkCount(PreviewData.oaBootstrap), 4);
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
    expect(find.byKey(const Key('new-friends-empty')), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1_outlined), findsOneWidget);
    expect(tester.widget<Text>(find.text('暂无新的好友申请')).style?.fontSize, 13);
    expect(tester.getTopLeft(find.text('暂无新的好友申请')).dy, lessThan(220));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'add-friend lookup keeps direct-chat permission separate from friendship',
    (tester) async {
      var searchedAccount = '';
      final currentMemberId = PreviewData.imBootstrap.currentMember.id;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactPresenceRefresherProvider.overrideWithValue(() async {}),
            imBootstrapProvider.overrideWith(
              (ref) async => PreviewData.imBootstrap,
            ),
            imDepartmentsProvider.overrideWith(
              (ref) async => PreviewData.imDepartments,
            ),
            pendingFriendApplicationsProvider.overrideWith(
              (ref) async => const [],
            ),
            memberAccountSearcherProvider.overrideWithValue((account) async {
              searchedAccount = account;
              if (account == 'self.account') {
                return [
                  ImSearchResult(
                    type: 'member',
                    id: currentMemberId,
                    displayName: '当前成员',
                    username: account,
                  ),
                ];
              }
              return [
                ImSearchResult(
                  type: 'member',
                  id: 'member-test03',
                  displayName: 'Test Terminal 03',
                  username: account,
                  departmentName: '集团总部',
                  isFriend: account == 'existing.friend',
                  canStartDirect: account != 'external.account',
                ),
              ];
            }),
          ],
          child: const MaterialApp(home: ContactsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('添加好友'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('friend-search-sheet')), findsOneWidget);
      expect(find.byKey(const Key('friend-search-close')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('friend-search-field'))).height,
        34,
      );
      expect(find.text('添加好友'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('friend-search-field')),
        'test03',
      );
      await tester.pump();
      expect(
        find.text('未找到该终端账号'),
        findsNothing,
        reason: 'typing is not an executed search',
      );
      await tester.tap(find.byKey(const Key('friend-search-submit')));
      await tester.pumpAndSettle();

      expect(searchedAccount, 'test03');
      expect(find.byKey(const Key('friend-search-sheet')), findsOneWidget);
      expect(find.byKey(const Key('friend-search-result')), findsOneWidget);
      expect(find.text('Test Terminal 03'), findsOneWidget);
      expect(find.text('test03 · 集团总部 · 状态未知'), findsOneWidget);
      expect(find.byKey(const Key('friend-search-action')), findsOneWidget);
      expect(find.text('发消息'), findsOneWidget);
      expect(find.text('验证消息'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('friend-search-field')))
            .controller
            ?.text,
        'test03',
      );

      await tester.enterText(
        find.byKey(const Key('friend-search-field')),
        'external.account',
      );
      await tester.tap(find.byKey(const Key('friend-search-submit')));
      await tester.pumpAndSettle();

      expect(find.text('申请好友'), findsOneWidget);
      expect(find.byKey(const Key('friend-search-sheet')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('friend-search-field')),
        'existing.friend',
      );
      await tester.tap(find.byKey(const Key('friend-search-submit')));
      await tester.pumpAndSettle();

      expect(find.text('发消息'), findsOneWidget);
      expect(find.byKey(const Key('friend-search-sheet')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('friend-search-field')),
        'self.account',
      );
      await tester.tap(find.byKey(const Key('friend-search-submit')));
      await tester.pumpAndSettle();

      expect(find.text('未找到该终端账号'), findsOneWidget);
      expect(find.byKey(const Key('friend-search-result')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'add-friend lookup keeps pending and failed searches off the result branch',
    (tester) async {
      final pending = Completer<List<ImSearchResult>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contactPresenceRefresherProvider.overrideWithValue(() async {}),
            imBootstrapProvider.overrideWith(
              (ref) async => PreviewData.imBootstrap,
            ),
            imDepartmentsProvider.overrideWith(
              (ref) async => PreviewData.imDepartments,
            ),
            pendingFriendApplicationsProvider.overrideWith(
              (ref) async => const [],
            ),
            memberAccountSearcherProvider.overrideWithValue((account) {
              if (account == 'lookup.error') {
                return Future<List<ImSearchResult>>.error(
                  'network unavailable',
                );
              }
              return pending.future;
            }),
          ],
          child: const MaterialApp(home: ContactsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('添加好友'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('friend-search-field')),
        'missing.account',
      );
      await tester.tap(find.byKey(const Key('friend-search-submit')));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('friend-search-result')), findsNothing);
      expect(tester.takeException(), isNull);

      pending.complete(const []);
      await tester.pumpAndSettle();
      expect(find.text('未找到该终端账号'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(
        find.byKey(const Key('friend-search-field')),
        'lookup.error',
      );
      await tester.tap(find.byKey(const Key('friend-search-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('搜索失败'), findsOneWidget);
      expect(find.byKey(const Key('friend-search-result')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final repeatAccount in [false, true]) {
    testWidgets(
      'friend search edits release pending requests and ignore stale results repeat=$repeatAccount',
      (tester) async {
        final first = Completer<List<ImSearchResult>>();
        final second = Completer<List<ImSearchResult>>();
        var searches = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              contactPresenceRefresherProvider.overrideWithValue(() async {}),
              imBootstrapProvider.overrideWith(
                (ref) async => PreviewData.imBootstrap,
              ),
              imDepartmentsProvider.overrideWith(
                (ref) async => PreviewData.imDepartments,
              ),
              pendingFriendApplicationsProvider.overrideWith(
                (ref) async => const [],
              ),
              memberAccountSearcherProvider.overrideWithValue(
                (account) => ++searches == 1 ? first.future : second.future,
              ),
            ],
            child: const MaterialApp(home: ContactsPage()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('添加好友'));
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('friend-search-field'));
        final submit = find.byKey(const Key('friend-search-submit'));
        await tester.enterText(field, 'first.account');
        await tester.tap(submit);
        await tester.pump();
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        await tester.enterText(field, 'second.account');
        if (repeatAccount) await tester.enterText(field, 'first.account');
        await tester.pump();
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
        await tester.tap(submit);
        await tester.pump();
        expect(searches, 2);
        first.complete([
          ImSearchResult(
            type: 'member',
            id: 'stale',
            displayName: '旧查询结果',
            username: 'first.account',
          ),
        ]);
        await tester.pump();
        expect(find.text('旧查询结果'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        second.complete([
          ImSearchResult(
            type: 'member',
            id: 'fresh',
            displayName: '当前查询结果',
            username: repeatAccount ? 'first.account' : 'second.account',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('当前查询结果'), findsOneWidget);
        expect(find.text('旧查询结果'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

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

      expect(find.text('林晨'), findsNothing);
      expect(
        find.byKey(const Key('department-group-department-hq')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('department-group-department-shanghai')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('department-group-department-hq')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('department-group-department-shanghai')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('department-group-department-shanghai')),
      );
      await tester.pumpAndSettle();

      expect(find.text('林晨'), findsOneWidget);
      expect(find.text('我'), findsOneWidget);
      expect(find.text('term.sh01'), findsNothing);
      expect(find.text('企业通讯录'), findsNothing);
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
      expect(find.byTooltip('发送消息'), findsNothing);
      expect(find.byTooltip('联系人操作'), findsNothing);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);

      await tester.tap(
        find.byKey(const Key('organization-department-selector')),
      );
      await tester.pumpAndSettle();
      expect(find.text('选择部门'), findsOneWidget);
      expect(find.byKey(const Key('department-picker-sheet')), findsOneWidget);
      expect(find.byKey(const Key('department-picker-close')), findsOneWidget);

      await tester.tap(find.text('深圳运营部').last);
      await tester.pumpAndSettle();

      expect(find.text('冯逸'), findsNothing);
      await tester.tap(
        find.byKey(const Key('department-group-department-shenzhen')),
      );
      await tester.pumpAndSettle();

      expect(find.text('冯逸'), findsOneWidget);
      expect(find.text('林晨'), findsNothing);
      expect(find.text('叶青'), findsNothing);
      expect(find.text('唐泽'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('organization directory expands contacts while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final source = PreviewData.imBootstrap;
    final departmentId = source.currentMember.departmentId;
    final departmentName = source.currentMember.departmentName;
    final contacts = List.generate(
      65,
      (index) => ImMember(
        id: 'directory-member-$index',
        username: 'directory.$index',
        displayName: '通讯录成员 $index',
        isOnline: index.isEven,
        departmentId: departmentId,
        departmentName: departmentName,
        canStartDirect: true,
        lastSeenAt: DateTime(2026, 9, 1, 8),
      ),
    );
    final bootstrap = ImBootstrap(
      currentMember: source.currentMember,
      conversations: source.conversations,
      contacts: contacts,
      permissions: source.permissions,
      config: source.config,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactPresenceRefresherProvider.overrideWithValue(() async {}),
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

    expect(find.text('通讯录成员 64'), findsNothing);
    expect(find.textContaining('加载更多'), findsNothing);
    await tester.tap(find.byKey(const Key('department-group-department-hq')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('department-group-$departmentId')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('department-page-footer-$departmentId')),
      findsNothing,
    );
    await tester.drag(
      find.byKey(const Key('contacts-page-scroll')),
      const Offset(0, -2400),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('contacts-page-scroll')),
      const Offset(0, -2400),
    );
    await tester.pumpAndSettle();

    expect(find.text('通讯录成员 64'), findsOneWidget);
    expect(
      find.byKey(Key('department-page-footer-$departmentId')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large organization builds departments before member rows', (
    tester,
  ) async {
    const root = ImDepartment(
      id: 'large-root',
      name: '集团总部',
      code: 'ROOT',
      parentId: '',
      sortOrder: 0,
    );
    final departments = <ImDepartment>[
      root,
      for (var index = 0; index < 100; index += 1)
        ImDepartment(
          id: 'large-department-$index',
          name: '业务部门 $index',
          code: 'D$index',
          parentId: root.id,
          sortOrder: index,
        ),
    ];
    final contacts = <ImMember>[
      for (var index = 0; index < 2000; index += 1)
        ImMember(
          id: 'large-member-$index',
          username: 'large.$index',
          displayName: '大组织成员 $index',
          isOnline: index.isEven,
          departmentId: 'large-department-${index ~/ 20}',
          departmentName: '业务部门 ${index ~/ 20}',
          canStartDirect: true,
        ),
    ];
    const currentMember = ImMember(
      id: 'large-current',
      username: 'large.current',
      displayName: '当前成员',
      isOnline: true,
      departmentId: 'large-department-0',
      departmentName: '业务部门 0',
    );
    final bootstrap = ImBootstrap(
      currentMember: currentMember,
      conversations: const [],
      contacts: contacts,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactPresenceRefresherProvider.overrideWithValue(() async {}),
          imBootstrapProvider.overrideWith((ref) async => bootstrap),
          imDepartmentsProvider.overrideWith((ref) async => departments),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: const MaterialApp(home: ContactsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('department-group-large-root')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('department-group-large-department-0')),
      findsNothing,
    );
    expect(find.text('大组织成员 0'), findsNothing);

    await tester.tap(find.byKey(const Key('department-group-large-root')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('department-group-large-department-0')),
      findsOneWidget,
    );
    expect(find.text('大组织成员 0'), findsNothing);

    await tester.tap(
      find.byKey(const Key('department-group-large-department-0')),
    );
    await tester.pumpAndSettle();
    expect(find.text('大组织成员 0'), findsOneWidget);
    expect(find.text('大组织成员 20'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

    await tester.tap(find.byKey(const Key('department-group-department-hq')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('department-group-department-shanghai')),
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
          imDepartmentsProvider.overrideWith(
            (ref) async => PreviewData.imDepartments,
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
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
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
            imMemberPresenceProjectionProvider.overrideWith(() => FixtureMemberPresence(PreviewData.imBootstrap.contacts)),
            contactPresenceRefresherProvider.overrideWithValue(() async {}),
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

    await tester.tap(find.byKey(const Key('department-group-department-hq')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('department-group-department-east-data')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('最近上线 08-13'), findsOneWidget);
  });

  testWidgets('contacts refresh authoritative presence on entry and pull', (
    tester,
  ) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactPresenceRefresherProvider.overrideWithValue(() async {
            refreshCount += 1;
          }),
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

    expect(refreshCount, 1);
    final refresh = tester.state<RefreshIndicatorState>(
      find.byType(RefreshIndicator),
    );
    final refreshFuture = refresh.show();
    await tester.pumpAndSettle();
    await refreshFuture;

    expect(refreshCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offstage contacts stop polling and stale presence is hidden after failure',
    (tester) async {
      var calls = 0;
      var fail = false;
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
          ProviderScope(
            overrides: [
              imMemberPresenceProjectionProvider.overrideWith(() => FixtureMemberPresence(PreviewData.imBootstrap.contacts)),
              contactPresenceRefresherProvider.overrideWithValue(() async {
              calls++;
              if (fail) throw StateError('offline');
            }),
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
          child: MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, enabled, child) =>
                  TickerMode(enabled: enabled, child: child!),
              child: const ContactsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.byKey(const Key('department-group-department-hq')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('department-group-department-shenzhen')),
      );
      await tester.pumpAndSettle();
      expect(find.text('在线'), findsOneWidget);
      visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 90));
      expect(calls, 1);
      fail = true;
      visible.value = true;
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('状态未知'), findsOneWidget);
      expect(find.text('在线'), findsNothing);
      fail = false;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(find.text('在线'), findsOneWidget);
    },
  );

  testWidgets('通讯录实时通道断开时不冒充在线状态', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          contactPresenceRefresherProvider.overrideWithValue(() async {}),
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

    await tester.tap(find.byKey(const Key('department-group-department-hq')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('department-group-department-shenzhen')),
    );
    await tester.pumpAndSettle();

    expect(find.text('状态未知'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
  });

  testWidgets(
    'all apps preserves the server workbench order and application routes',
    (tester) async {
      final catalog = OaApplicationCatalog(
        catalogVersion: 'long-label-test',
        items: [
          ...PreviewData.oaCatalog.items,
          const OaApplicationCatalogItem(
            applicationKey: 'attendance.long-label',
            name: '分级请款审批',
            category: '考勤',
            iconKey: 'payment',
            iconDataUrl: null,
            displayOrder: 11,
            configurationKind: 'approval',
            configurationId: 'long-label-configuration',
            approvalTemplateId: 'long-label-template',
            allowOfflineDraft: true,
            availabilitySource: 'department',
            sourceDepartmentId: 'department-1',
          ),
        ],
      );
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
            oaApplicationCatalogProvider.overrideWith((ref) async => catalog),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('all-app-category-考勤')), findsOneWidget);
      expect(find.byKey(const Key('all-app-category-费用')), findsOneWidget);
      expect(find.text('我的常用'), findsNothing);
      expect(find.text('请假申请'), findsOneWidget);
      expect(find.text('报销申请'), findsOneWidget);
      expect(find.text('日程'), findsNothing);
      expect(find.text('网络诊断'), findsNothing);
      final leaveLabel = tester.widget<Text>(find.text('请假申请'));
      expect(leaveLabel.maxLines, 3);
      expect(leaveLabel.overflow, TextOverflow.ellipsis);
      expect(leaveLabel.textAlign, TextAlign.center);
      final longLabel = tester.widget<Text>(find.text('分级请款审批'));
      expect(longLabel.maxLines, 3);
      expect(longLabel.overflow, TextOverflow.ellipsis);
      expect(
        tester
            .getSize(
              find.byKey(const Key('all-app-label-attendance.long-label')),
            )
            .height,
        lessThanOrEqualTo(38),
      );
      expect(
        tester
            .getSize(find.byKey(const Key('all-app-icon-attendance.leave')))
            .height,
        32,
      );
      expect(
        tester.getSize(find.byKey(const Key('all-app-catalog-surface'))).height,
        lessThanOrEqualTo(202),
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
      expect(find.byKey(const Key('all-app-category-采购')), findsOneWidget);
      expect(find.byKey(const Key('all-app-category-行政')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('all-app-category-采购'))).dy,
        lessThan(tester.getTopLeft(find.text('采购申请')).dy),
      );
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

  testWidgets(
    'workbench does not present an offline cache as a true empty result',
    (tester) async {
      final source = PreviewData.oaBootstrap;
      final empty = OaBootstrap(
        currentMemberId: source.currentMemberId,
        displayName: source.displayName,
        todos: const [],
        announcements: const [],
        templates: source.templates,
        approvalRequests: const [],
        notifications: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith((ref) async => empty),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
            oaSyncAvailabilityProvider.overrideWithValue(
              OaSyncAvailability.unavailable,
            ),
          ],
          child: const MaterialApp(home: WorkbenchPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('workbench-approval-offline')),
        findsOneWidget,
      );
      expect(find.text('本机记录'), findsOneWidget);
      expect(find.text('本机暂无审批记录'), findsOneWidget);
      expect(find.text('暂无审批事项'), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const Key('workbench-approval-offline')))
            .height,
        lessThanOrEqualTo(34),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workbench keeps the approval empty state provisional while syncing',
    (tester) async {
      final source = PreviewData.oaBootstrap;
      final empty = OaBootstrap(
        currentMemberId: source.currentMemberId,
        displayName: source.displayName,
        todos: const [],
        announcements: const [],
        templates: source.templates,
        approvalRequests: const [],
        notifications: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith((ref) async => empty),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
            oaSyncAvailabilityProvider.overrideWithValue(
              OaSyncAvailability.connecting,
            ),
          ],
          child: const MaterialApp(home: WorkbenchPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('同步中'), findsOneWidget);
      expect(find.text('正在同步审批'), findsOneWidget);
      expect(find.text('暂无审批事项'), findsNothing);
      expect(tester.takeException(), isNull);
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
    expect(find.byKey(const Key('all-app-category-费用')), findsOneWidget);
    expect(find.byKey(const Key('all-app-category-考勤')), findsNothing);
    expect(find.text('我的常用'), findsNothing);
    expect(find.text('请假申请'), findsNothing);
    expect(find.text('网络诊断'), findsNothing);

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('暂无匹配应用'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/group_management_page.dart';

void main() {
  testWidgets('muted members load the next page while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var secondPageCalls = 0;
    await _pumpGroupManagement(
      tester,
      mutedLoader: (_, {int page = 1, int pageSize = 50}) async {
        if (page == 2) {
          secondPageCalls += 1;
          return ImGroupManagementPage<ImMutedGroupMember>(
            items: [_mutedMember(21)],
            page: 2,
            pageSize: 20,
            total: 21,
          );
        }
        return ImGroupManagementPage<ImMutedGroupMember>(
          items: List.generate(20, (index) => _mutedMember(index + 1)),
          page: 1,
          pageSize: 20,
          total: 21,
        );
      },
    );

    expect(secondPageCalls, 0);
    expect(find.text('加载更多'), findsNothing);
    expect(find.text('禁言成员 21'), findsNothing);
    await tester.drag(
      find.byKey(const Key('group-management-page-scroll-0')),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();

    expect(secondPageCalls, 1);
    expect(find.text('禁言成员 21'), findsOneWidget);
    expect(find.byKey(const Key('group-management-page-footer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty first page continues automatically', (tester) async {
    var secondPageCalls = 0;
    await _pumpGroupManagement(
      tester,
      mutedLoader: (_, {int page = 1, int pageSize = 50}) async {
        if (page == 2) {
          secondPageCalls += 1;
          return ImGroupManagementPage<ImMutedGroupMember>(
            items: [_mutedMember(1)],
            page: 2,
            pageSize: 1,
            total: 1,
          );
        }
        return const ImGroupManagementPage<ImMutedGroupMember>(
          items: [],
          page: 1,
          pageSize: 1,
          total: 1,
        );
      },
    );

    expect(secondPageCalls, 1);
    expect(find.text('禁言成员 1'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paging failure keeps content and exposes explicit retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var secondPageCalls = 0;
    await _pumpGroupManagement(
      tester,
      mutedLoader: (_, {int page = 1, int pageSize = 50}) async {
        if (page == 2) {
          secondPageCalls += 1;
          if (secondPageCalls == 1) throw StateError('temporary paging error');
          return ImGroupManagementPage<ImMutedGroupMember>(
            items: [_mutedMember(21)],
            page: 2,
            pageSize: 20,
            total: 21,
          );
        }
        return ImGroupManagementPage<ImMutedGroupMember>(
          items: List.generate(20, (index) => _mutedMember(index + 1)),
          page: 1,
          pageSize: 20,
          total: 21,
        );
      },
    );

    await tester.drag(
      find.byKey(const Key('group-management-page-scroll-0')),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    expect(secondPageCalls, 1);
    expect(find.text('重新加载'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重新加载'));
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(secondPageCalls, 2);
    expect(find.text('禁言成员 21'), findsOneWidget);
    expect(find.text('重新加载'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each management tab keeps an independent page loader', (
    tester,
  ) async {
    var mutedPage2 = 0;
    var requestPage2 = 0;
    var managerPage2 = 0;
    var noticePage2 = 0;
    await _pumpGroupManagement(
      tester,
      mutedLoader: (_, {int page = 1, int pageSize = 50}) async {
        if (page == 2) mutedPage2 += 1;
        return ImGroupManagementPage<ImMutedGroupMember>(
          items: [_mutedMember(page)],
          page: page,
          pageSize: 1,
          total: 2,
        );
      },
      requestsLoader: (_, {int page = 1, int pageSize = 50}) async {
        if (page == 2) requestPage2 += 1;
        return ImGroupManagementPage<ImGroupJoinRequest>(
          items: [
            ImGroupJoinRequest(
              id: 'request-$page',
              applicantMemberId: 'request-member-$page',
              applicantName: '申请人 $page',
              status: 'pending',
            ),
          ],
          page: page,
          pageSize: 1,
          total: 2,
        );
      },
      managersLoader: (_, {int page = 1, int pageSize = 50}) async {
        if (page == 2) managerPage2 += 1;
        return ImGroupManagementPage<ImMember>(
          items: [
            ImMember(
              id: 'manager-$page',
              username: 'manager.$page',
              displayName: '管理成员 $page',
              isOnline: page == 1,
              groupRole: 'manager',
            ),
          ],
          page: page,
          pageSize: 1,
          total: 2,
        );
      },
      noticesLoader: (_, {int page = 1, int pageSize = 50}) async {
        if (page == 2) noticePage2 += 1;
        return ImGroupManagementPage<ImGroupNotice>(
          items: [
            ImGroupNotice(
              id: 'notice-$page',
              type: 'group.profile.updated',
              actorName: '操作人 $page',
            ),
          ],
          page: page,
          pageSize: 1,
          total: 2,
        );
      },
    );

    expect(mutedPage2, 1);
    await tester.tap(find.text('入群 2'));
    await tester.pumpAndSettle();
    expect(requestPage2, 1);
    expect(find.text('申请人 2'), findsOneWidget);

    await tester.tap(find.text('管理员 2'));
    await tester.pumpAndSettle();
    expect(managerPage2, 1);
    expect(find.text('管理成员 2'), findsOneWidget);
    expect(find.text('manager.2'), findsNothing);

    await tester.tap(find.text('记录 2'));
    await tester.pumpAndSettle();
    expect(noticePage2, 1);
    expect(find.textContaining('操作人 2'), findsOneWidget);
    expect(mutedPage2, 1);
    expect(find.text('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpGroupManagement(
  WidgetTester tester, {
  required ImGroupMutedMembersPageLoader mutedLoader,
  ImGroupManagersPageLoader? managersLoader,
  ImGroupJoinRequestsPageLoader? requestsLoader,
  ImGroupNoticesPageLoader? noticesLoader,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imGroupManagementCapabilitiesLoaderProvider.overrideWithValue(
          (_) async => const ImGroupManagementCapabilities(),
        ),
        imGroupMutedMembersPageLoaderProvider.overrideWithValue(mutedLoader),
        imGroupManagersPageLoaderProvider.overrideWithValue(
          managersLoader ?? _emptyManagers,
        ),
        imGroupJoinRequestsPageLoaderProvider.overrideWithValue(
          requestsLoader ?? _emptyRequests,
        ),
        imGroupNoticesPageLoaderProvider.overrideWithValue(
          noticesLoader ?? _emptyNotices,
        ),
        imGroupProfileRefresherProvider.overrideWithValue(
          (_) async => const ImGroupProfile(
            conversationId: 'group-test',
            title: '测试群',
            notice: '',
          ),
        ),
      ],
      child: const MaterialApp(
        home: GroupManagementPage(conversationId: 'group-test'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ImMutedGroupMember _mutedMember(int index) => ImMutedGroupMember(
  member: ImMember(
    id: 'muted-member-$index',
    username: 'muted.$index',
    displayName: '禁言成员 $index',
    isOnline: index.isEven,
  ),
  mutedUntil: DateTime(2026, 9, 2, 8),
);

Future<ImGroupManagementPage<ImMember>> _emptyManagers(
  String _, {
  int page = 1,
  int pageSize = 50,
}) async => const ImGroupManagementPage<ImMember>(
  items: [],
  page: 1,
  pageSize: 50,
  total: 0,
);

Future<ImGroupManagementPage<ImGroupJoinRequest>> _emptyRequests(
  String _, {
  int page = 1,
  int pageSize = 50,
}) async => const ImGroupManagementPage<ImGroupJoinRequest>(
  items: [],
  page: 1,
  pageSize: 50,
  total: 0,
);

Future<ImGroupManagementPage<ImGroupNotice>> _emptyNotices(
  String _, {
  int page = 1,
  int pageSize = 50,
}) async => const ImGroupManagementPage<ImGroupNotice>(
  items: [],
  page: 1,
  pageSize: 50,
  total: 0,
);

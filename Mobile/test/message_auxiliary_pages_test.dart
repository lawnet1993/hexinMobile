import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/message_assistant_page.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/message_favorites_page.dart';

void main() {
  testWidgets('群发助手支持搜索、全选和紧凑提交按钮', (tester) async {
    final view = tester.view;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imAssistantTasksPageProvider.overrideWith(
            (ref, page) async => ImListPage(
              items: page == 1
                  ? PreviewData.imAssistantTasks
                  : const <ImAssistantTask>[],
              page: page,
              pageSize: 50,
              total: PreviewData.imAssistantTasks.length,
            ),
          ),
        ],
        child: const MaterialApp(home: MessageAssistantPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('群发助手'), findsOneWidget);
    expect(find.text('已选 0 人'), findsOneWidget);
    expect(find.textContaining('已完成'), findsOneWidget);
    expect(find.textContaining('成功 3/3'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '叶青');
    await tester.pump();
    expect(find.text('叶青'), findsNWidgets(2));
    expect(find.text('冯逸'), findsNothing);

    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('已选 1 人'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '测试群发消息');
    await tester.pump();
    final submit = find.widgetWithText(FilledButton, '提交群发任务');
    expect(submit, findsOneWidget);
    expect(tester.getSize(submit).height, 40);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(find.text('已选 0 人'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('群发任务记录滚动到底自动读取下一页', (tester) async {
    final source = PreviewData.imAssistantTasks.single;
    ImAssistantTask task(int index, String content) => ImAssistantTask(
      id: 'assistant-auto-$index',
      messageKind: source.messageKind,
      content: content,
      attachmentJson: source.attachmentJson,
      status: source.status,
      receiverCount: source.receiverCount,
      successCount: source.successCount,
      failureCount: source.failureCount,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
    );
    var secondPageCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imAssistantTasksPageProvider.overrideWith((ref, page) async {
            if (page == 2) secondPageCalls += 1;
            return ImListPage(
              items: page == 1
                  ? List.generate(
                      20,
                      (index) => task(index + 1, '第一页群发任务 ${index + 1}'),
                    )
                  : [task(21, '自动加载的第二页任务')],
              page: page,
              pageSize: 20,
              total: 21,
            );
          }),
        ],
        child: const MaterialApp(home: MessageAssistantPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(secondPageCalls, 0);
    expect(find.text('自动加载的第二页任务'), findsNothing);
    expect(find.textContaining('加载更多'), findsNothing);

    final pageScroll = find.byKey(const Key('assistant-page-scroll'));
    final outerScrollable = find
        .descendant(of: pageScroll, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.text('第一页群发任务 20'),
      600,
      scrollable: outerScrollable,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.text('第一页群发任务 20'), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(secondPageCalls, 1);
    expect(find.text('自动加载的第二页任务'), findsOneWidget);
    expect(find.byKey(const Key('assistant-task-page-footer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏列表可打开原会话且操作按钮保持紧凑', (tester) async {
    final router = GoRouter(
      initialLocation: '/favorites',
      routes: [
        GoRoute(
          path: '/favorites',
          builder: (_, _) => const MessageFavoritesPage(),
        ),
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
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imFavoritesPageProvider.overrideWith(
            (ref, page) async => ImListPage(
              items: page == 1
                  ? PreviewData.imFavorites
                  : const <ImFavoriteMessage>[],
              page: page,
              pageSize: 50,
              total: PreviewData.imFavorites.length,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.byTooltip('打开会话'), findsNWidgets(2));
    expect(find.byTooltip('取消收藏'), findsNWidgets(2));
    expect(
      tester.getSize(find.byTooltip('打开会话').first).height,
      lessThanOrEqualTo(40),
    );

    await tester.tap(find.byTooltip('打开会话').first);
    await tester.pumpAndSettle();
    expect(find.text('chat:ops'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏列表在短首屏自动读取后续分页', (tester) async {
    final router = GoRouter(
      initialLocation: '/favorites',
      routes: [
        GoRoute(
          path: '/favorites',
          builder: (_, _) => const MessageFavoritesPage(),
        ),
        GoRoute(
          path: '/chat/:id',
          builder: (_, state) =>
              Scaffold(body: Text('chat:${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final first = PreviewData.imFavorites.first;
    final second = PreviewData.imFavorites.last;
    var secondPageCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          imFavoritesPageProvider.overrideWith((ref, page) async {
            if (page == 2) secondPageCalls += 1;
            return ImListPage(
              items: page == 1 ? [first] : [second],
              page: page,
              pageSize: 1,
              total: 2,
            );
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(secondPageCalls, 1);
    expect(find.textContaining('接口联调清单'), findsOneWidget);
    expect(find.textContaining('加载更多'), findsNothing);
    expect(find.byKey(const Key('favorite-page-footer')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

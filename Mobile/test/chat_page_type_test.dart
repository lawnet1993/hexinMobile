import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/chat_page.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  test('member presence keeps the backend last-seen timestamp', () {
    final member = ImMember.fromJson(const {
      'id': 'member-1',
      'userName': 'term.member1',
      'displayName': '成员一',
      'isOnline': false,
      'lastSeenAt': '2026-08-30T08:12:00Z',
    });

    expect(member.isOnline, isFalse);
    expect(member.lastSeenAt, DateTime.utc(2026, 8, 30, 8, 12).toLocal());
  });

  testWidgets('group chat uses real members and group profile', (tester) async {
    await _pumpChat(tester, 'ops');

    expect(find.text('3 位成员'), findsOneWidget);
    expect(find.text('周报请在每周一 10:00 前提交'), findsOneWidget);
    expect(find.text('8 位成员'), findsNothing);
    expect(find.byTooltip('群聊详情'), findsOneWidget);

    await tester.tap(find.byTooltip('群聊详情'));
    await tester.pumpAndSettle();
    expect(find.text('群聊详情'), findsOneWidget);
    expect(find.text('群成员（3）'), findsOneWidget);
    expect(find.text('3 位成员 · 3 人在线'), findsOneWidget);
    expect(find.text('复制群聊'), findsOneWidget);
    expect(find.text('真实群公告'), findsNothing);
    expect(find.text('周报请在每周一 10:00 前提交'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CompactSwitch).first),
      const Size(36, 24),
    );

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部群成员'), findsOneWidget);
    expect(find.text('在线'), findsNWidgets(3));
  });

  testWidgets('direct chat uses the other member profile', (tester) async {
    await _pumpChat(tester, 'tang');

    expect(find.text('唐泽'), findsOneWidget);
    expect(find.textContaining('term.gz01'), findsOneWidget);
    expect(find.byTooltip('个人资料'), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsNothing);

    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('在线'), findsWidgets);
    expect(find.text('账号'), findsOneWidget);
    expect(find.text('term.gz01'), findsWidgets);
    expect(find.text('共享文件'), findsOneWidget);
    expect(find.text('关联审批'), findsOneWidget);
    expect(find.text('共同任务'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('删除单聊'), findsOneWidget);
    expect(find.text('复制群聊'), findsNothing);
    expect(find.text('解散群聊'), findsNothing);
    expect(find.text('群成员（3）'), findsNothing);
  });

  testWidgets(
    'direct chat aligns desktop resource tabs without mixing groups',
    (tester) async {
      await _pumpChat(
        tester,
        'tang',
        messages: PreviewData.conversationMessages('tang'),
      );

      expect(find.text('聊天'), findsOneWidget);
      expect(find.text('文件 4'), findsOneWidget);
      expect(find.text('任务 1'), findsOneWidget);

      await tester.tap(find.text('文件 4'));
      await tester.pumpAndSettle();
      expect(find.text('文件 1'), findsOneWidget);
      expect(find.text('图片/视频 2'), findsOneWidget);
      expect(find.text('链接 1'), findsOneWidget);
      expect(find.text('接口联调清单.pdf'), findsOneWidget);
      expect(find.byTooltip('发送'), findsNothing);

      await tester.tap(find.text('图片/视频 2'));
      await tester.pumpAndSettle();
      expect(find.text('接口流程图.png'), findsOneWidget);
      expect(find.text('终端绑定演示.mp4'), findsOneWidget);

      await tester.tap(find.text('链接 1'));
      await tester.pumpAndSettle();
      expect(find.text('https://docs.example.com/im/mobile'), findsOneWidget);

      await tester.tap(find.text('任务 1'));
      await tester.pumpAndSettle();
      expect(find.text('终端绑定申请'), findsOneWidget);
      expect(find.text('新建'), findsOneWidget);
      expect(find.byTooltip('发送'), findsNothing);

      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      expect(find.text('新建共同任务'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, '创建')).height,
        40,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('新建共同任务'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('attachment actions stay compact and isolate direct-only tasks', (
    tester,
  ) async {
    await _pumpChat(tester, 'tang');

    await tester.tap(find.byTooltip('附件'));
    await tester.pumpAndSettle();

    expect(find.text('发送内容'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('音频'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-attachment-file')), findsOneWidget);
    expect(find.text('联系人'), findsOneWidget);
    expect(find.text('创建任务'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('chat-attachment-image')))
          .height,
      72,
    );

    await tester.tap(find.text('创建任务'));
    await tester.pumpAndSettle();
    expect(find.text('新建共同任务'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await _pumpChat(tester, 'ops');
    await tester.tap(find.byTooltip('附件'));
    await tester.pumpAndSettle();
    expect(find.text('创建任务'), findsNothing);
    expect(find.text('联系人'), findsOneWidget);
  });

  testWidgets('new demo direct chat preserves the selected contact identity', (
    tester,
  ) async {
    const conversationId = 'demo-direct-1';
    await _pumpChat(
      tester,
      conversationId,
      messages: PreviewData.conversationMessages(conversationId),
    );

    expect(find.text('冯逸'), findsOneWidget);
    expect(find.textContaining('term.sz02'), findsOneWidget);
    expect(find.text('唐泽'), findsNothing);
    expect(find.text('周报数据已更新，请帮忙确认。'), findsOneWidget);
    expect(find.byTooltip('个人资料'), findsOneWidget);
  });

  testWidgets('direct message actions never expose group-only controls', (
    tester,
  ) async {
    await _pumpChat(tester, 'tang', messages: PreviewData.messages);

    await tester.longPress(find.text('6 月运营数据看板已更新，请大家查收。'));
    await tester.pumpAndSettle();

    expect(find.text('回复'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('设为群置顶'), findsNothing);
  });

  testWidgets('group message actions expose group pin control', (tester) async {
    await _pumpChat(tester, 'ops', messages: PreviewData.messages);

    await tester.longPress(find.text('6 月运营数据看板已更新，请大家查收。'));
    await tester.pumpAndSettle();

    expect(find.text('设为群置顶'), findsOneWidget);
  });

  testWidgets('reply action follows the server message configuration', (
    tester,
  ) async {
    final source = PreviewData.imBootstrap;
    final bootstrap = ImBootstrap(
      currentMember: source.currentMember,
      conversations: source.conversations,
      contacts: source.contacts,
      permissions: source.permissions,
      config: const ImClientConfig(message: ImMessageConfig(reply: false)),
    );
    await _pumpChat(
      tester,
      'tang',
      messages: PreviewData.messages,
      bootstrap: bootstrap,
    );

    await tester.longPress(find.text('6 月运营数据看板已更新，请大家查收。'));
    await tester.pumpAndSettle();

    expect(find.text('回复'), findsNothing);
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  String conversationId, {
  List<ImMessage> messages = const [],
  ImBootstrap? bootstrap,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imBootstrapProvider.overrideWith(
          (ref) async => bootstrap ?? PreviewData.imBootstrap,
        ),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        conversationMessagesProvider.overrideWith((ref, id) async => messages),
        conversationMembersProvider.overrideWith(
          (ref, id) async => PreviewData.conversationMembers(id),
        ),
        conversationMemberPageProvider.overrideWith((ref, key) async {
          final members = PreviewData.conversationMembers(key.conversationId);
          return ImMemberPage(
            items: members,
            page: 1,
            pageSize: key.pageSize,
            total: members.length,
          );
        }),
        groupProfileProvider.overrideWith(
          (ref, id) async => PreviewData.groupProfile(id),
        ),
        groupManagersProvider.overrideWith(
          (ref, id) async => PreviewData.groupManagers(id),
        ),
      ],
      child: MaterialApp(
        home: ChatPage(conversationId: conversationId, enablePresence: false),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

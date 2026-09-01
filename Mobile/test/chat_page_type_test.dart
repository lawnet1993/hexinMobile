import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/chat_page.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  test('message window memory is bounded and evicts the oldest chat', () {
    final memory = ConversationMessageWindowMemory()
      ..remember('oldest', take: 160, hasOlder: false);
    for (var index = 0; index < 32; index++) {
      memory.remember('conversation-$index', take: 80, hasOlder: true);
    }

    final restored = memory.restore('oldest');
    expect(restored.take, ConversationMessageWindowMemory.initialTake);
    expect(restored.hasOlder, isTrue);
  });

  test('latest reconciliation coalesces and throttles rapid reopens', () async {
    var now = DateTime.utc(2026, 8, 31, 8);
    var loadCount = 0;
    final pending = Completer<bool>();
    final coordinator = ConversationLatestReconcileCoordinator(now: () => now);
    Future<bool> loader(String conversationId) {
      loadCount += 1;
      return pending.future;
    }

    final first = coordinator.reconcile('ops', loader);
    final second = coordinator.reconcile('ops', loader);
    expect(loadCount, 1);
    pending.complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);

    expect(await coordinator.reconcile('ops', loader), isFalse);
    expect(loadCount, 1);

    now = now.add(const Duration(seconds: 11));
    expect(await coordinator.reconcile('ops', loader), isTrue);
    expect(loadCount, 2);
  });

  test('message window reuses the hot cache on immediate reopen', () async {
    var loadCount = 0;
    final message = ImMessage(
      id: 'hot-reopen-message',
      conversationId: 'hot-reopen',
      sequence: 1,
      senderId: 'member-1',
      content: '已缓存消息',
      kind: 'text',
      createdAt: DateTime.utc(2026, 8, 31, 8),
    );
    final container = ProviderContainer(
      overrides: [
        conversationMessageWindowLoaderProvider.overrideWithValue((
          conversationId, {
          take,
        }) async {
          loadCount += 1;
          return [message];
        }),
      ],
    );
    addTearDown(container.dispose);
    const key = (conversationId: 'hot-reopen', take: 80);

    final first = container.listen(
      conversationMessageWindowProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    expect(
      await container.read(conversationMessageWindowProvider(key).future),
      [message],
    );
    expect(loadCount, 1);
    first.close();
    await Future<void>.delayed(Duration.zero);

    final reopened = container.listen(
      conversationMessageWindowProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    expect(
      await container.read(conversationMessageWindowProvider(key).future),
      [message],
    );
    expect(loadCount, 1);
    reopened.close();
  });

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

    await tester.tap(find.byTooltip('提及成员'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mention-picker-sheet')), findsOneWidget);
    expect(find.byKey(const Key('mention-picker-list')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('mention-picker-search'))).height,
      34,
    );
    expect(
      tester.getSize(find.byKey(const Key('mention-picker-member-me'))).height,
      50,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();

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

    expect(find.byTooltip('添加成员'), findsOneWidget);
    await tester.tap(find.byTooltip('添加成员'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-member-picker-sheet')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('group-member-picker-search')))
          .height,
      34,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('group-member-picker-submit')))
          .height,
      36,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    expect(find.text('全部群成员'), findsOneWidget);
    expect(
      find.byKey(const Key('group-member-directory-sheet')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('group-member-directory-search')))
          .height,
      34,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('group-member-directory-member-me')))
          .height,
      54,
    );
    expect(find.byType(Divider), findsNothing);
    expect(find.text('在线'), findsNWidgets(3));

    await tester.tap(find.byKey(const Key('group-member-directory-member-3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.text('管理 唐泽'), findsOneWidget);
    expect(find.text('设为管理员'), findsOneWidget);
    expect(find.text('禁言 24 小时'), findsOneWidget);
    expect(find.text('转让群主'), findsOneWidget);
    expect(find.text('移出群聊'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();
  });

  testWidgets('outgoing message exposes an icon-only lazy read receipt', (
    tester,
  ) async {
    final currentMember = PreviewData.imBootstrap.currentMember;
    var loadCount = 0;
    final outgoing = ImMessage(
      id: 'sent-with-receipt',
      conversationId: 'direct',
      sequence: 12,
      senderId: currentMember.id,
      content: '请查收',
      kind: 'text',
      createdAt: DateTime.utc(2026, 9, 1, 3, 50),
    );
    await _pumpChat(
      tester,
      'direct',
      messages: [outgoing],
      readReceiptLoader: (messageId) async {
        loadCount += 1;
        expect(messageId, outgoing.id);
        return ImMessageReadReceipt(
          conversationId: 'direct',
          messageId: messageId,
          sequence: outgoing.sequence,
          readCount: 1,
          totalRecipientCount: 1,
          isReadByAll: true,
          peerRead: true,
          readers: [
            ImMessageReadMember(
              memberId: 'member-1',
              username: 'tang.ze',
              displayName: '唐泽',
              role: 'member',
              readAt: DateTime.utc(2026, 9, 1, 3, 51),
            ),
          ],
        );
      },
    );

    final receiptAction = find.byKey(
      const ValueKey<String>('message-read-receipt-sent-with-receipt'),
    );
    expect(receiptAction, findsOneWidget);
    expect(find.text('回执'), findsNothing);
    expect(loadCount, 0);
    final receiptRect = tester.getRect(receiptAction);
    final bubbleTextRect = tester.getRect(find.text('请查收'));
    expect(
      (receiptRect.center.dy - bubbleTextRect.center.dy).abs(),
      lessThan(12),
      reason: '已读状态应与消息气泡保持同一视觉行，不能折到气泡下方',
    );

    await tester.tap(receiptAction);
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(
      find.byKey(const Key('message-read-receipts-sheet')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('message-read-receipts-list')))
          .height,
      52,
    );
    expect(find.text('已读 1/1'), findsOneWidget);
    expect(find.text('唐泽'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read receipt entry follows the server permission', (
    tester,
  ) async {
    final source = PreviewData.imBootstrap;
    final bootstrap = ImBootstrap(
      currentMember: source.currentMember,
      conversations: source.conversations,
      contacts: source.contacts,
      permissions: const ImPermissionSnapshot(readReceipt: false),
      config: source.config,
    );
    final outgoing = ImMessage(
      id: 'receipt-disabled',
      conversationId: 'direct',
      sequence: 13,
      senderId: source.currentMember.id,
      content: '权限关闭时不显示入口',
      kind: 'text',
      createdAt: DateTime.utc(2026, 9, 1, 3, 52),
    );

    await _pumpChat(
      tester,
      'direct',
      messages: [outgoing],
      bootstrap: bootstrap,
    );

    expect(
      find.byKey(
        const ValueKey<String>('message-read-receipt-receipt-disabled'),
      ),
      findsNothing,
    );
    expect(find.text('回执'), findsNothing);
    await tester.longPress(find.text('权限关闭时不显示入口'));
    await tester.pumpAndSettle();
    expect(find.text('查看已读'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('group composer follows server mute state and member role', (
    tester,
  ) async {
    final source = PreviewData.imBootstrap;
    final mutedProfile = ImGroupProfile(
      conversationId: 'ops',
      title: '华南运营协作',
      notice: '',
      muted: true,
      status: 'active',
    );
    ImMember currentWithRole(String role) => ImMember(
      id: source.currentMember.id,
      username: source.currentMember.username,
      displayName: source.currentMember.displayName,
      isOnline: source.currentMember.isOnline,
      groupRole: role,
    );
    final peers = PreviewData.conversationMembers('ops')
        .where((member) => member.id != source.currentMember.id)
        .toList();

    await _pumpChat(
      tester,
      'ops',
      groupProfile: mutedProfile,
      members: [currentWithRole('member'), ...peers],
    );
    var input = tester.widget<TextField>(
      find.byKey(const Key('chat-message-input')),
    );
    expect(input.enabled, isFalse);
    expect(input.decoration?.hintText, '全员禁言中');
    IconButton iconButton(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );
    expect(iconButton('附件').onPressed, isNull);
    expect(iconButton('表情').onPressed, isNull);
    expect(iconButton('发送').onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpChat(
      tester,
      'ops',
      groupProfile: mutedProfile,
      members: [currentWithRole('owner'), ...peers],
    );
    input = tester.widget<TextField>(
      find.byKey(const Key('chat-message-input')),
    );
    expect(input.enabled, isTrue);
    expect(input.decoration?.hintText, '输入消息');
    expect(iconButton('附件').onPressed, isNotNull);
  });

  testWidgets('group composer fails closed until the current role is loaded', (
    tester,
  ) async {
    final profileCompleter = Completer<ImGroupProfile?>();
    final peers = PreviewData.conversationMembers('ops')
        .where(
          (member) => member.id != PreviewData.imBootstrap.currentMember.id,
        )
        .toList();

    await _pumpChat(
      tester,
      'ops',
      members: peers,
      groupProfileLoader: (_) => profileCompleter.future,
      settle: false,
    );
    await tester.pump();

    var input = tester.widget<TextField>(
      find.byKey(const Key('chat-message-input')),
    );
    expect(input.enabled, isFalse);
    expect(input.decoration?.hintText, '群聊状态加载中');

    profileCompleter.complete(
      const ImGroupProfile(
        conversationId: 'ops',
        title: '华南运营协作',
        notice: '',
        muted: true,
        status: 'active',
        currentUserRole: 'owner',
      ),
    );
    await tester.pumpAndSettle();

    input = tester.widget<TextField>(
      find.byKey(const Key('chat-message-input')),
    );
    expect(input.enabled, isTrue);
    expect(input.decoration?.hintText, '输入消息');
  });

  testWidgets('mention picker virtualizes and searches a large group', (
    tester,
  ) async {
    var fullMemberLoads = 0;
    final memberPageKeywords = <String>[];
    final members = <ImMember>[
      PreviewData.imBootstrap.currentMember,
      ...List<ImMember>.generate(
        2000,
        (index) => ImMember(
          id: 'large-member-$index',
          username: 'large$index',
          displayName: '成员 $index',
          departmentName: '大群测试部',
          isOnline: index.isEven,
        ),
      ),
    ];
    await _pumpChat(
      tester,
      'ops',
      members: members,
      onFullMembersRequested: (_) => fullMemberLoads += 1,
      onMemberPageRequested: memberPageKeywords.add,
    );

    expect(find.text('2001 位成员'), findsOneWidget);
    expect(fullMemberLoads, 0);
    expect(memberPageKeywords, contains(''));

    await tester.tap(find.byTooltip('提及成员'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mention-picker-list')), findsOneWidget);
    expect(
      find.byKey(const Key('mention-picker-member-large-member-1999')),
      findsNothing,
    );
    expect(find.byType(ListTile).evaluate().length, lessThan(40));

    await tester.enterText(
      find.byKey(const Key('mention-picker-search')),
      'large1999',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mention-picker-member-large-member-1999')),
      findsOneWidget,
    );
    expect(find.text('成员 1999'), findsOneWidget);
    expect(memberPageKeywords, contains('large1999'));
    expect(fullMemberLoads, 0);
  });

  testWidgets('direct chat uses the other member profile', (tester) async {
    await _pumpChat(tester, 'tang');

    expect(find.text('唐泽'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.textContaining('term.gz01'), findsNothing);
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
    expect(find.text('发起群聊'), findsOneWidget);
    await tester.tap(find.text('发起群聊'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-group-sheet')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('create-group-title-input'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('create-group-submit'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('create-group-member-1'))).height,
      50,
    );
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('删除单聊'), findsOneWidget);
    expect(find.text('复制群聊'), findsNothing);
    expect(find.text('解散群聊'), findsNothing);
    expect(find.text('群成员（3）'), findsNothing);
  });

  testWidgets(
    'direct chat prioritizes real offline status over identity text',
    (tester) async {
      final source = PreviewData.imBootstrap;
      final offlineMember = ImMember(
        id: '3',
        username: 'term.gz01',
        displayName: '唐泽',
        isOnline: false,
        departmentId: 'department-shanghai',
        departmentName: '上海运营部',
        lastSeenAt: DateTime(2026, 8, 30, 16, 12),
      );
      final bootstrap = ImBootstrap(
        currentMember: source.currentMember,
        conversations: source.conversations,
        contacts: [
          ...source.contacts.where((member) => member.id != offlineMember.id),
          offlineMember,
        ],
        permissions: source.permissions,
        config: source.config,
      );

      await _pumpChat(
        tester,
        'tang',
        bootstrap: bootstrap,
        members: [source.currentMember, offlineMember],
      );

      expect(find.text('离线 · 08-30 16:12'), findsOneWidget);
      expect(find.textContaining('term.gz01'), findsNothing);
    },
  );

  testWidgets('pure emoji messages use the desktop enlarged treatment', (
    tester,
  ) async {
    final messages = <ImMessage>[
      ImMessage(
        id: 'emoji-single',
        conversationId: 'tang',
        sequence: 1,
        senderId: '3',
        content: '😀',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 1),
      ),
      ImMessage(
        id: 'emoji-family',
        conversationId: 'tang',
        sequence: 2,
        senderId: '3',
        content: '👨‍👩‍👧‍👦 ❤️',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 1, 1),
      ),
      ImMessage(
        id: 'emoji-keycap',
        conversationId: 'tang',
        sequence: 3,
        senderId: '3',
        content: '1️⃣',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 1, 2),
      ),
      ImMessage(
        id: 'emoji-mixed',
        conversationId: 'tang',
        sequence: 4,
        senderId: '3',
        content: '😀 收到',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 1, 3),
      ),
    ];
    await _pumpChat(tester, 'tang', messages: messages);

    for (final id in const ['emoji-single', 'emoji-family', 'emoji-keycap']) {
      final text = tester.widget<Text>(
        find.byKey(ValueKey<String>('message-text-$id')),
      );
      expect(text.style?.fontSize, 30);
    }
    final mixed = tester.widget<Text>(
      find.byKey(const ValueKey<String>('message-text-emoji-mixed')),
    );
    expect(mixed.style?.fontSize, isNull);
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
      expect(
        tester
            .getSize(find.byKey(const Key('chat-message-input-shell')))
            .height,
        40,
      );
      expect(
        find.ancestor(
          of: find.byTooltip('表情'),
          matching: find.byKey(const Key('chat-message-input-shell')),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(find.byTooltip('发送')), const Size(40, 40));
      await tester.tap(find.byTooltip('搜索聊天记录'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-current-search')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('chat-current-search'))).height,
        34,
      );
      expect(
        tester.getSize(find.byKey(const Key('chat-current-search-close'))),
        const Size(34, 34),
      );
      await tester.tap(find.byKey(const Key('chat-current-search-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat-current-search')), findsNothing);
      final chatTab = tester.getRect(
        find.byKey(const ValueKey<String>('chat-resource-tab-聊天')),
      );
      final chatLabel = tester.getRect(find.text('聊天'));
      final chatIndicator = tester.getRect(
        find.byKey(const ValueKey<String>('chat-resource-tab-indicator-聊天')),
      );
      expect((chatLabel.center.dx - chatTab.center.dx).abs(), lessThan(0.1));
      expect(chatIndicator.bottom, closeTo(chatTab.bottom, 0.1));
      expect(chatIndicator.top - chatTab.center.dy, greaterThanOrEqualTo(14));

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
      expect(find.byKey(const Key('shared-task-create-sheet')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('shared-task-title-input'))).height,
        36,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('shared-task-create-button')))
            .height,
        36,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('shared-task-create-button')))
            .width,
        lessThan(120),
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

    await tester.tap(find.byTooltip('附件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-contact-picker-sheet')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('chat-contact-picker-search')))
          .height,
      34,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    final firstContact = PreviewData.imBootstrap.contacts.first;
    expect(
      tester
          .getSize(
            find.byKey(
              ValueKey('chat-contact-picker-member-${firstContact.id}'),
            ),
          )
          .height,
      50,
    );
    await tester.tap(find.byTooltip('关闭').last);
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
    expect(find.text('在线'), findsOneWidget);
    expect(find.textContaining('term.sz02'), findsNothing);
    expect(find.text('唐泽'), findsNothing);
    expect(
      find.textContaining('https://docs.example.com/im/mobile'),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('周报数据已更新，请帮忙确认。'), findsOneWidget);
    expect(find.byTooltip('个人资料'), findsOneWidget);
    await tester.tap(find.byTooltip('个人资料'));
    await tester.pumpAndSettle();
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('term.sz02'), findsWidgets);
    expect(find.text('唐泽'), findsNothing);
  });

  testWidgets('direct message actions never expose group-only controls', (
    tester,
  ) async {
    await _pumpChat(tester, 'tang', messages: PreviewData.messages);

    await tester.longPress(find.text('6 月运营数据看板已更新，请大家查收。'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.text('消息操作'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('设为群置顶'), findsNothing);

    await tester.tap(find.text('转发'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.text('转发到'), findsOneWidget);
    expect(find.text('华南运营协作'), findsOneWidget);
    expect(find.text('群聊'), findsWidgets);
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();
  });

  testWidgets('group message actions expose group pin control', (tester) async {
    await _pumpChat(tester, 'ops', messages: PreviewData.messages);

    await tester.longPress(find.text('6 月运营数据看板已更新，请大家查收。'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.text('设为群置顶'), findsOneWidget);
  });

  testWidgets('video message renders a cached real preview before metadata', (
    tester,
  ) async {
    final preview = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLQkwAAAABJRU5ErkJggg==',
    );
    final message = ImMessage(
      id: 'video-message',
      conversationId: 'ops',
      sequence: 12,
      senderId: '1',
      // The server mirrors the attachment name into content for video
      // messages. It must not be rendered below the preview a second time.
      content: '现场验收.mp4',
      kind: 'video',
      attachments: const [
        ImMessageAttachment(
          id: 'video-attachment',
          type: 'video',
          fileName: '现场验收.mp4',
          contentType: 'video/mp4',
          size: 4096,
          sha256: 'video-sha256',
          durationSeconds: 18,
        ),
      ],
      createdAt: DateTime(2026, 8, 31, 12),
    );

    await _pumpChat(tester, 'ops', messages: [message], videoPreview: preview);

    expect(find.byKey(const ValueKey('message-video-preview')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('message-video-preview'))),
      const Size(200, 112),
    );
    expect(find.text('0:18'), findsOneWidget);
    expect(find.text('现场验收.mp4'), findsNothing);
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('message-video-preview')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(semantics.properties.label, '视频预览，现场验收.mp4');
  });

  testWidgets('chat image decodes at thumbnail width before full preview', (
    tester,
  ) async {
    final imageMessage = PreviewData.conversationMessages('tang')
        .where((message) => message.kind == 'image')
        .single;
    await _pumpChat(tester, 'tang', messages: [imageMessage]);

    final image = tester.widget<Image>(
      find.byKey(
        const ValueKey<String>(
          'message-image-thumbnail:direct-image-1:demo-image-1',
        ),
      ),
    );
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, 630);
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

  testWidgets('outgoing status distinguishes pending and failed delivery', (
    tester,
  ) async {
    final pending = ImMessage(
      id: 'local-pending',
      conversationId: 'ops',
      sequence: 0,
      senderId: PreviewData.imBootstrap.currentMember.id,
      clientMessageId: 'pending-1',
      content: '等待发送',
      kind: 'text',
      createdAt: DateTime.utc(2026, 8, 31, 8),
      localStatus: ImLocalMessageStatus.pending,
    );
    final failed = ImMessage(
      id: 'local-failed',
      conversationId: 'ops',
      sequence: 0,
      senderId: PreviewData.imBootstrap.currentMember.id,
      clientMessageId: 'failed-1',
      content: '发送失败的消息',
      kind: 'text',
      createdAt: DateTime.utc(2026, 8, 31, 8, 1),
      localStatus: ImLocalMessageStatus.failed,
    );

    await _pumpChat(tester, 'ops', messages: [pending, failed]);

    expect(find.text('发送中'), findsOneWidget);
    expect(find.text('发送失败，点此重试'), findsOneWidget);
  });

  testWidgets('scrolling to the top loads older messages without a button', (
    tester,
  ) async {
    final messages = List<ImMessage>.generate(
      30,
      (index) => ImMessage(
        id: 'history-$index',
        conversationId: 'ops',
        sequence: index + 100,
        senderId: index.isEven
            ? PreviewData.imBootstrap.currentMember.id
            : 'member-1',
        content: '历史消息 $index',
        kind: 'text',
        createdAt: DateTime.utc(2026, 8, 31, 8, index),
      ),
    );
    var loadCount = 0;
    int? requestedBeforeSequence;
    final windowMemory = ConversationMessageWindowMemory();
    await _pumpChat(
      tester,
      'ops',
      messages: messages,
      messageWindowMemory: windowMemory,
      olderMessageLoader: (conversationId, {beforeSequence}) async {
        loadCount += 1;
        requestedBeforeSequence = beforeSequence;
        return [
          ImMessage(
            id: 'older-page',
            conversationId: conversationId,
            sequence: 99,
            senderId: 'member-1',
            content: '更早的消息',
            kind: 'text',
            createdAt: DateTime.utc(2026, 8, 31, 7, 59),
          ),
        ];
      },
    );

    expect(find.text('加载更早消息'), findsNothing);
    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    await tester.drag(list, const Offset(0, 1800));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(requestedBeforeSequence, 100);
    final rememberedWindow = windowMemory.restore('ops');
    expect(rememberedWindow.take, 81);
    expect(rememberedWindow.hasOlder, isFalse);
  });

  testWidgets('reopening a chat restores its expanded exhausted window', (
    tester,
  ) async {
    final messages = List<ImMessage>.generate(
      30,
      (index) => ImMessage(
        id: 'reopen-history-$index',
        conversationId: 'ops',
        sequence: index + 1,
        senderId: 'member-1',
        content: '已加载消息 $index',
        kind: 'text',
        createdAt: DateTime.utc(2026, 8, 31, 8, index),
      ),
    );
    final windowMemory = ConversationMessageWindowMemory()
      ..remember('ops', take: 160, hasOlder: false);
    int? requestedTake;
    var olderLoadCount = 0;

    await _pumpChat(
      tester,
      'ops',
      messages: messages,
      messageWindowMemory: windowMemory,
      onWindowRequested: (take) => requestedTake = take,
      olderMessageLoader: (conversationId, {beforeSequence}) async {
        olderLoadCount += 1;
        return const <ImMessage>[];
      },
    );

    expect(requestedTake, 160);
    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    await tester.drag(list, const Offset(0, 1800));
    await tester.pumpAndSettle();
    expect(olderLoadCount, 0);
  });

  testWidgets('failed older message load retries on the next upward scroll', (
    tester,
  ) async {
    final messages = List<ImMessage>.generate(
      30,
      (index) => ImMessage(
        id: 'retry-history-$index',
        conversationId: 'ops',
        sequence: index + 100,
        senderId: index.isEven
            ? PreviewData.imBootstrap.currentMember.id
            : 'member-1',
        content: '历史消息 $index',
        kind: 'text',
        createdAt: DateTime.utc(2026, 8, 31, 8, index),
      ),
    );
    var loadCount = 0;
    await _pumpChat(
      tester,
      'ops',
      messages: messages,
      olderMessageLoader: (conversationId, {beforeSequence}) async {
        loadCount += 1;
        if (loadCount == 1) throw StateError('temporary failure');
        return [
          ImMessage(
            id: 'retry-older-page',
            conversationId: conversationId,
            sequence: 99,
            senderId: 'member-1',
            content: '重试后的更早消息',
            kind: 'text',
            createdAt: DateTime.utc(2026, 8, 31, 7, 59),
          ),
        ];
      },
    );

    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    await tester.drag(list, const Offset(0, 1800));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('请稍后再次上滑'), findsOneWidget);

    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 1800));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(loadCount, 2);
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  String conversationId, {
  List<ImMessage> messages = const [],
  ImBootstrap? bootstrap,
  List<ImMember>? members,
  ImGroupProfile? groupProfile,
  Future<ImGroupProfile?> Function(String conversationId)? groupProfileLoader,
  Uint8List? videoPreview,
  ConversationOlderMessageLoader? olderMessageLoader,
  ConversationMessageWindowMemory? messageWindowMemory,
  ValueChanged<int>? onWindowRequested,
  ValueChanged<String>? onFullMembersRequested,
  ValueChanged<String>? onMemberPageRequested,
  ImMessageReadReceiptLoader? readReceiptLoader,
  bool settle = true,
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
        conversationMessageWindowProvider.overrideWith((ref, key) async {
          onWindowRequested?.call(key.take);
          return messages;
        }),
        if (messageWindowMemory != null)
          conversationMessageWindowMemoryProvider.overrideWithValue(
            messageWindowMemory,
          ),
        conversationOlderMessageLoaderProvider.overrideWithValue(
          olderMessageLoader ??
              (conversationId, {beforeSequence}) async => const <ImMessage>[],
        ),
        imMediaCacheAccountLoaderProvider.overrideWithValue(
          () async => 'widget-test-account',
        ),
        imMessageImageBytesLoaderProvider.overrideWithValue(
          (messageId, imageId) async => _testImageBytes,
        ),
        imMessageImageDiskCacheReaderProvider.overrideWithValue(
          ({
            required accountId,
            required imageId,
            required sha256Value,
          }) async => null,
        ),
        imMessageImageDiskCacheWriterProvider.overrideWithValue(
          ({
            required accountId,
            required imageId,
            required sha256Value,
            required bytes,
          }) async {},
        ),
        imVideoPreviewProvider.overrideWith(
          (ref, key) async => videoPreview == null
              ? null
              : ImVideoPreviewSource.memory(videoPreview),
        ),
        if (readReceiptLoader != null)
          imMessageReadReceiptLoaderProvider.overrideWithValue(
            readReceiptLoader,
          ),
        conversationMembersProvider.overrideWith((ref, id) async {
          onFullMembersRequested?.call(id);
          return members ?? PreviewData.conversationMembers(id);
        }),
        conversationMemberPageProvider.overrideWith((ref, key) async {
          onMemberPageRequested?.call(key.keyword);
          final source =
              members ?? PreviewData.conversationMembers(key.conversationId);
          final keyword = key.keyword.trim().toLowerCase();
          final filtered = source
              .where(
                (member) =>
                    keyword.isEmpty ||
                    member.displayName.toLowerCase().contains(keyword) ||
                    member.username.toLowerCase().contains(keyword) ||
                    member.departmentName.toLowerCase().contains(keyword),
              )
              .toList(growable: false);
          final start = (key.page - 1) * key.pageSize;
          return ImMemberPage(
            items: start >= filtered.length
                ? const <ImMember>[]
                : filtered
                      .skip(start)
                      .take(key.pageSize)
                      .toList(growable: false),
            page: key.page,
            pageSize: key.pageSize,
            total: filtered.length,
          );
        }),
        groupProfileProvider.overrideWith(
          (ref, id) =>
              groupProfileLoader?.call(id) ??
              Future<ImGroupProfile?>.value(
                groupProfile ?? PreviewData.groupProfile(id),
              ),
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
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final Uint8List _testImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

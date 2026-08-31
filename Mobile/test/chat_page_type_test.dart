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
    await _pumpChat(
      tester,
      'ops',
      messages: messages,
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
  Uint8List? videoPreview,
  ConversationOlderMessageLoader? olderMessageLoader,
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
        conversationMessageWindowProvider.overrideWith(
          (ref, key) async => messages,
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
        conversationMembersProvider.overrideWith(
          (ref, id) async => members ?? PreviewData.conversationMembers(id),
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

final Uint8List _testImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

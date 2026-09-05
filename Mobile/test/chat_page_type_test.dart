import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/theme/app_colors.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/im_sync_coordinator.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/chat_page.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/chat_composer_drafts.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';
import 'support/fixture_member_presence.dart';
import 'support/chat_composer_fixture.dart';

final _memberTestScopeProvider = NotifierProvider<_MemberTestScope, String>(
  _MemberTestScope.new,
);

class _MemberTestScope extends Notifier<String> {
  @override
  String build() => '';
  void change() => state = 'other';
}

void main() {
  testWidgets('composer reply captured before send does not leak into next draft', (tester) async {
    final fixture = (await tester.runAsync(ChatComposerFixture.create))!;
    addTearDown(fixture.store.close);
    addTearDown(fixture.cipher.release);
    final original = ImMessage(id: 'quoted-message', conversationId: 'ops',
      sequence: 1, senderId: 'member-1', content: 'Original question', kind: 'text',
      createdAt: DateTime(2026, 9, 3));
    await _pumpChat(tester, 'ops', repository: fixture.repository, messages: [original]);
    await tester.longPress(find.byKey(const ValueKey('message-bubble-quoted-message')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回复'));
    await tester.pumpAndSettle();
    final input = find.byKey(const Key('chat-message-input'));
    expect(tester.widget<TextField>(input).decoration!.hintText, '回复消息');
    await tester.enterText(input, 'reply body');
    fixture.cipher.hold();
    await tester.tap(find.byTooltip('发送'));
    await _waitForComposerWrite(tester, fixture);
    expect(tester.widget<TextField>(input).decoration!.hintText, '输入消息');
    await tester.enterText(input, 'next body');
    fixture.cipher.release();
    await _finishComposer(tester);
    await tester.tap(find.byTooltip('发送'));
    await _finishComposer(tester);
    final queued = (await tester.runAsync(() => fixture.store.dueOutbox('me')))!;
    expect(queued.map((m) => m.replyToMessageId), ['quoted-message', null]);
    await tester.pumpWidget(const SizedBox());
  });

  for (final failure in [false, true]) {
    testWidgets('composer account transition ignores old completion: failure=$failure', (tester) async {
      final fixture = (await tester.runAsync(ChatComposerFixture.create))!;
      addTearDown(fixture.store.close);
      addTearDown(fixture.cipher.release);
      await _pumpChat(tester, 'ops', repository: fixture.repository, testMemberScope: true);
      final input = find.byKey(const Key('chat-message-input'));
      final container = ProviderScope.containerOf(tester.element(find.byType(ChatPage)));
      fixture.cipher.hold(failure: failure);
      await tester.enterText(input, 'previous account');
      await tester.tap(find.byTooltip('发送'));
      await _waitForComposerWrite(tester, fixture);
      container.read(_memberTestScopeProvider.notifier).change();
      await tester.pump();
      await tester.enterText(input, 'new account draft');
      fixture.cipher.release();
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(tester.widget<TextField>(input).controller!.text, 'new account draft');
      expect(find.byTooltip('重试未入库消息'), findsNothing);
      expect(container.read(unstoredChatDraftsProvider), isEmpty);
      expect((await tester.runAsync(() => fixture.store.dueOutbox('other')))!, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final nextText in ['first draft', '', '新消息😊']) {
    testWidgets('composer preserves next input exactly: $nextText', (tester) async {
      final fixture = (await tester.runAsync(ChatComposerFixture.create))!;
      addTearDown(fixture.store.close);
      addTearDown(fixture.cipher.release);
      await _pumpChat(tester, 'ops', repository: fixture.repository);
      final input = find.byKey(const Key('chat-message-input'));
      fixture.cipher.hold();
      await tester.enterText(input, 'first draft');
      final send = tester.widget<IconButton>(find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '发送',
      )).onPressed!;
      send();
      await _waitForComposerWrite(tester, fixture);
      await tester.enterText(input, nextText);
      send(); // stale button callback / duplicate tap must not enqueue again.
      fixture.cipher.release();
      await _finishComposer(tester);
      expect(tester.widget<TextField>(input).controller!.text, nextText);
      expect((await tester.runAsync(() => fixture.store.dueOutbox('me')))!.length, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('composer snapshots mentions and new mention survives old commit', (tester) async {
    final fixture = (await tester.runAsync(ChatComposerFixture.create))!;
    addTearDown(fixture.store.close);
    addTearDown(fixture.cipher.release);
    await _pumpChat(tester, 'ops', repository: fixture.repository);
    final input = find.byKey(const Key('chat-message-input'));
    final members = PreviewData.conversationMembers('ops');
    final original = members.first;
    final next = members.last;
    expect(next.id, isNot(original.id));
    await tester.tap(find.byTooltip('提及成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('mention-picker-member-${original.id}')));
    await tester.pumpAndSettle();
    fixture.cipher.hold();
    await tester.tap(find.byTooltip('发送'));
    await _waitForComposerWrite(tester, fixture);
    await tester.tap(find.byTooltip('提及成员'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(Key('mention-picker-member-${next.id}')));
    await tester.pump(const Duration(milliseconds: 350));
    fixture.cipher.release();
    await _finishComposer(tester);
    expect(tester.widget<TextField>(input).controller!.text, '@${next.displayName} ');
    await tester.tap(find.byTooltip('发送'));
    await _finishComposer(tester);
    final queued = (await tester.runAsync(() => fixture.store.dueOutbox('me')))!;
    expect(queued.map((m) => m.mentionedMemberIds), [[original.id], [next.id]]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('composer failure after leaving chat is recoverable on reopen', (tester) async {
    final fixture = (await tester.runAsync(ChatComposerFixture.create))!;
    addTearDown(fixture.store.close);
    addTearDown(fixture.cipher.release);
    await _pumpChat(tester, 'ops', repository: fixture.repository, openFromLauncher: true);
    await tester.tap(find.text('打开测试会话'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatPage)));
    fixture.cipher.hold(failure: true);
    await tester.enterText(find.byKey(const Key('chat-message-input')), 'retain after route leave');
    await tester.tap(find.byTooltip('发送'));
    await _waitForComposerWrite(tester, fixture);
    Navigator.of(tester.element(find.byType(ChatPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    fixture.cipher.release();
    for (var i = 0; i < 100 && (container.read(unstoredChatDraftsProvider)['ops']?.isEmpty ?? true); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(container.read(unstoredChatDraftsProvider)['ops']!.single.content, 'retain after route leave');
    await tester.tap(find.text('打开测试会话'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('重试未入库消息'), findsOneWidget);
    await tester.tap(find.byTooltip('重试未入库消息'));
    await _finishComposer(tester);
    expect((await tester.runAsync(() => fixture.store.dueOutbox('me')))!.single.content, 'retain after route leave');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('composer clears at tap and preserves typing during local commit', (tester) async {
    final fixture = (await tester.runAsync(ChatComposerFixture.create))!;
    addTearDown(fixture.store.close);
    addTearDown(fixture.cipher.release);
    await _pumpChat(tester, 'ops', repository: fixture.repository);
    final input = find.byKey(const Key('chat-message-input'));
    fixture.cipher.hold();
    await tester.enterText(input, 'first draft');
    await tester.tap(find.byTooltip('发送'));
    await _waitForComposerWrite(tester, fixture);
    final immediatelyCleared = tester.widget<TextField>(input).controller!.text.isEmpty;
    await tester.enterText(input, 'second draft');
    fixture.cipher.release();
    await _finishComposer(tester);
    expect(immediatelyCleared, isTrue);
    expect(tester.widget<TextField>(input).controller!.text, 'second draft');
    final queued = await tester.runAsync(() => fixture.store.dueOutbox('me'));
    expect(queued!.map((m) => m.content), ['first draft']);
    await tester.tap(find.byTooltip('发送'));
    await _finishComposer(tester);
    final all = await tester.runAsync(() => fixture.store.dueOutbox('me'));
    expect(all!.map((m) => m.content), ['first draft', 'second draft']);
    expect(all.map((m) => m.clientMessageId).toSet().length, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('composer failed local commit keeps newer draft and retries original', (tester) async {
    final fixture = (await tester.runAsync(ChatComposerFixture.create))!;
    addTearDown(fixture.store.close);
    addTearDown(fixture.cipher.release);
    await _pumpChat(tester, 'ops', repository: fixture.repository);
    final input = find.byKey(const Key('chat-message-input'));
    fixture.cipher.hold(failure: true);
    await tester.enterText(input, 'original failed draft');
    await tester.tap(find.byTooltip('发送'));
    await _waitForComposerWrite(tester, fixture);
    await tester.enterText(input, 'new unsent draft');
    fixture.cipher.release();
    await _finishComposer(tester);
    expect(tester.widget<TextField>(input).controller!.text, 'new unsent draft');
    expect(await tester.runAsync(() => fixture.store.dueOutbox('me')), isEmpty);
    expect(find.byTooltip('重试未入库消息'), findsOneWidget);
    await tester.tap(find.byTooltip('重试未入库消息'));
    await _finishComposer(tester);
    expect(tester.widget<TextField>(input).controller!.text, 'new unsent draft');
    final queued = await tester.runAsync(() => fixture.store.dueOutbox('me'));
    expect(queued!.map((m) => m.content), ['original failed draft']);
    expect(find.byTooltip('重试未入库消息'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in ['image-one', 'image-grid', 'video', 'audio']) {
    for (final mine in [false, true]) {
      testWidgets('media geometry follows content width: $kind mine=$mine', (tester) async {
        final id = 'geometry-$kind-$mine';
        final isImage = kind.startsWith('image');
        final message = ImMessage(
          id: id,
          conversationId: 'ops',
          sequence: 40,
          senderId: mine ? PreviewData.imBootstrap.currentMember.id : 'member-1',
          content: '',
          kind: isImage ? 'image' : kind,
          images: isImage ? List.generate(kind == 'image-one' ? 1 : 4, (i) => ImMessageImage(
            id: 'geometry-image-$i', fileName: 'uat-$i.png', size: 68,
          )) : const [],
          attachments: isImage ? const [] : [ImMessageAttachment(
            id: 'geometry-media', type: kind, fileName: 'uat.$kind', size: 2048,
            contentType: '$kind/mp4', sha256: 'geometry-test-hash',
            durationSeconds: 18,
          )],
          createdAt: DateTime(2026, 9, 3, 10, 24),
        );
        await _pumpChat(tester, 'ops', messages: [message], videoPreview: _testImageBytes);
        final bubble = find.byKey(ValueKey('message-bubble-$id'));
        final width = kind == 'image-grid' ? 240.0 : kind == 'video' ? 200.0 : 210.0;
        final content = find.descendant(of: bubble, matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == width,
        )).first;
        expect(tester.getSize(bubble).width - tester.getSize(content).width,
          lessThanOrEqualTo(21), reason: 'Only 19dp padding plus incoming 2dp border, not a full-width metadata row');
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('media geometry image grid does not inherit screen safe-area padding', (tester) async {
    final image = PreviewData.conversationMessages('tang').firstWhere((message) => message.kind == 'image');
    await _pumpChat(tester, 'tang', messages: [image], wrapChat: (child) => MediaQuery(
      data: const MediaQueryData(size: Size(400, 800), padding: EdgeInsets.only(bottom: 28)),
      child: child,
    ));
    final bubble = find.byKey(ValueKey('message-bubble-${image.id}'));
    final grid = find.descendant(of: bubble, matching: find.byType(GridView));
    expect(tester.getSize(grid).height, 180);
    expect(tester.widget<GridView>(grid).padding, EdgeInsets.zero);
    expect(tester.takeException(), isNull);
  });
  for (final kind in ['image', 'video', 'audio']) {
    for (final mine in [false, true]) {
      testWidgets('media geometry narrow screen and large text: $kind mine=$mine', (tester) async {
        tester.view.physicalSize = const Size(900, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final id = 'narrow-$kind-$mine';
        final message = ImMessage(
          id: id, conversationId: 'ops', sequence: 1,
          senderId: mine ? PreviewData.imBootstrap.currentMember.id : 'geometry-sender',
          content: '', kind: kind,
          images: kind == 'image' ? List.generate(4, (i) => ImMessageImage(
            id: 'narrow-image-$i', fileName: 'uat.png', size: 68,
          )) : const [],
          attachments: kind == 'image' ? const [] : [ImMessageAttachment(
            id: 'narrow-attachment', type: kind,
            fileName: 'AI-UAT-这是一份较长名称的媒体文件.$kind',
            contentType: '$kind/mp4', size: 2048, sha256: 'narrow-fixture', durationSeconds: 18,
          )],
          replyTo: ImMessageReply(messageId: 'prior', senderId: 'geometry-sender',
            content: '需要保留完整上下文的较长引用内容', kind: 'text', createdAt: DateTime(2026, 9, 3)),
          createdAt: DateTime(2026, 9, 3, 10, 24),
        );
        await _pumpChat(tester, 'ops', messages: [message], videoPreview: _testImageBytes,
          members: const [ImMember(id: 'geometry-sender', username: 'fixture',
            displayName: 'AI-UAT-显示名称很长的群成员用于验证紧凑布局', isOnline: false)],
          wrapChat: (child) => Builder(builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.6)), child: child,
          )),
        );
        final rect = tester.getRect(find.byKey(ValueKey('message-bubble-$id')));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(300));
        if (!mine) {
          final name = tester.widget<Text>(find.text('AI-UAT-显示名称很长的群成员用于验证紧凑布局'));
          expect(name.maxLines, 1);
          expect(name.overflow, TextOverflow.ellipsis);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final hiddenMode in ['route', 'overlay', 'background', 'offstage']) {
    testWidgets('chat visibility prevents hidden reads and polling: $hiddenMode', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      var latest = 1;
      var enters = 0;
      var reconciles = 0;
      final reads = <int>[];
      await _pumpChat(
        tester,
        'ops',
        enablePresence: true,
        enterPresence: (_) async { enters++; },
        latestReconciler: (_) async { reconciles++; return false; },
        markVisibleRead: (_, sequence) async { reads.add(sequence); },
        messageWindowLoader: (_, {take}) async => List.generate(latest, (index) => ImMessage(
          id: 'visibility-$index',
          conversationId: 'ops',
          sequence: index + 1,
          senderId: 'member-1',
          content: '可见消息 ${index + 1}',
          kind: 'text',
          createdAt: DateTime.utc(2026, 9, 3, 0, index),
        )),
        wrapChat: (child) => ValueListenableBuilder<bool>(
          valueListenable: visible,
          child: child,
          builder: (_, value, child) => TickerMode(
            enabled: value,
            child: Offstage(offstage: !value, child: child),
          ),
        ),
      );
      expect(reads, [1]);
      expect(enters, 1);
      expect(reconciles, 1);
      final chatContext = tester.element(find.byType(ChatPage));
      final container = ProviderScope.containerOf(chatContext);
      final navigator = Navigator.of(chatContext);
      if (hiddenMode == 'route') {
        unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('覆盖聊天')))));
      } else if (hiddenMode == 'overlay') {
        unawaited(showModalBottomSheet<void>(
          context: chatContext,
          builder: (_) => const SizedBox(height: 500, child: Text('会话操作')),
        ));
      } else if (hiddenMode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else {
        visible.value = false;
      }
      await tester.pumpAndSettle();
      latest = 2;
      container.invalidate(conversationMessageWindowProvider((conversationId: 'ops', take: 80)));
      await tester.pumpAndSettle();
      expect(reads, [1], reason: 'offscreen layout is not proof that the user saw the message');
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      expect(enters, 1, reason: 'hidden chat must not renew active-conversation presence');
      expect(reconciles, 1, reason: 'global sync can continue without hidden-page polling');
      if (hiddenMode == 'route' || hiddenMode == 'overlay') {
        navigator.pop();
      } else if (hiddenMode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else {
        visible.value = true;
      }
      await tester.pumpAndSettle();
      expect(reads, [1, 2]);
      expect(enters, 2);
      expect(reconciles, 2);
      expect(find.text('可见消息 2').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('chat visibility coalesces a slow presence renewal', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final pending = Completer<void>();
    var enters = 0;
    await _pumpChat(
      tester, 'ops', enablePresence: true,
      enterPresence: (_) async { enters++; await pending.future; },
      latestReconciler: (_) async => false,
    );
    await tester.pump(const Duration(seconds: 75));
    expect(enters, 1);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 25));
    expect(enters, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('history 405 is actionable and retry can recover', (
    tester,
  ) async {
    var unavailable = true;
    var loads = 0;
    await _pumpChat(
      tester,
      'ops',
      messageWindowLoader: (id, {take}) async {
        loads += 1;
        if (unavailable) {
          final request = RequestOptions(
            path: '/api/im/conversations/ops/messages',
          );
          throw DioException.badResponse(
            statusCode: 405,
            requestOptions: request,
            response: Response<void>(requestOptions: request, statusCode: 405),
          );
        }
        return [
          ImMessage(
            id: 'recovered',
            sequence: 1,
            senderId: 'member-1',
            conversationId: 'ops',
            content: '接口恢复后的消息',
            kind: 'text',
            createdAt: DateTime.utc(2026, 9, 2),
          ),
        ];
      },
    );
    expect(find.text('消息加载失败'), findsOneWidget);
    expect(find.text('服务接口不兼容，请联系管理员'), findsOneWidget);
    expect(find.text('发送第一条消息开始协作'), findsNothing);
    unavailable = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('服务接口不兼容，请联系管理员'), findsNothing);
    expect(find.text('接口恢复后的消息'), findsOneWidget);
  });
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

  for (final conversationId in ['ops', 'tang']) {
    testWidgets(
      '$conversationId hot route reopen positions cached messages at the latest message',
      (tester) async {
        var loads = 0;
        var historyLoads = 0;
        await _pumpChat(
          tester,
          conversationId,
          openFromLauncher: true,
          useRealMessageWindow: true,
          onWindowRequested: (_) => loads++,
          messages: List.generate(
            80,
            (index) => ImMessage(
              id: 'hot-route-$index',
              conversationId: conversationId,
              sequence: index + 1,
              senderId: 'member-1',
              content: '缓存消息 $index${index % 3 == 0 ? '\n不等高的第二行\n第三行' : ''}',
              kind: 'text',
              createdAt: DateTime.utc(2026, 9, 2, 8, index),
            ),
          ),
          olderMessageLoader: (_, {beforeSequence}) async {
            historyLoads++;
            return [];
          },
        );
        for (var round = 0; round < 3; round++) {
          await tester.tap(find.text('打开测试会话'));
          await tester.pumpAndSettle();
          expect(
            find.text('缓存消息 79').hitTestable(),
            findsOneWidget,
            reason: 'route open $round must land at the latest cached message',
          );
          expect(
            loads,
            1,
            reason: 'reopening must reuse the existing message cache',
          );
          expect(
            historyLoads,
            0,
            reason: 'initial positioning must not load history',
          );
          if (round == 2) {
            final list = find.byKey(
              PageStorageKey<String>('chat-messages:$conversationId'),
            );
            await tester.drag(list, const Offset(0, 600));
            await tester.pumpAndSettle();
            final controller = tester.widget<ListView>(list).controller!;
            final readingOffset = controller.offset;
            expect(
              controller.position.maxScrollExtent - readingOffset,
              greaterThan(120),
            );
            ProviderScope.containerOf(
              tester.element(find.byType(ChatPage)),
            ).invalidate(conversationMessageRevisionProvider(conversationId));
            await tester.pumpAndSettle();
            expect(loads, 2);
            expect(
              controller.offset,
              closeTo(readingOffset, 1),
              reason: 'refreshing messages must not pull a history reader to the bottom',
            );
          }
          Navigator.of(tester.element(find.byType(ChatPage))).pop();
          await tester.pumpAndSettle();
        }
        // Dispose retained providers and their timers before the widget test ends.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

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

  testWidgets('offline group directory has no live presence dots', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      'ops',
      realtimeAvailability: ImRealtimeAvailability.unavailable,
    );
    await tester.tap(find.byTooltip('群聊详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看全部'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('group-member-directory-sheet'));
    expect(find.text('状态未知'), findsNWidgets(3));
    expect(
      tester
          .widgetList<Container>(
            find.descendant(of: sheet, matching: find.byType(Container)),
          )
          .where(
            (widget) =>
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).color ==
                    const Color(0xFF22B573),
          ),
      isEmpty,
    );
    expect(
      tester
          .widgetList<InitialAvatar>(
            find.descendant(of: sheet, matching: find.byType(InitialAvatar)),
          )
          .every((avatar) => avatar.online == null),
      isTrue,
    );
  });

  testWidgets(
    'group directory refresh keeps members on failure then recovers',
    (tester) async {
      var fail = false;
      var calls = 0;
      await _pumpChat(
        tester,
        'ops',
        memberPageLoader: (page, keyword) async {
          calls++;
          if (fail) throw StateError('offline');
          return ImMemberPage(
            items: PreviewData.conversationMembers('ops'),
            page: page,
            pageSize: 50,
            total: 3,
          );
        },
      );
      await tester.tap(find.byTooltip('群聊详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看全部'));
      await tester.pumpAndSettle();
      final previousCalls = calls;
      fail = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(previousCalls));
      expect(
        find.byKey(const Key('group-member-directory-member-me')),
        findsOneWidget,
      );
      expect(find.text('状态未知'), findsNWidgets(3));
      expect(find.text('在线'), findsNothing);
      fail = false;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('在线'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'group detail never derives total online count from member page',
    (tester) async {
      await _pumpChat(
        tester,
        'ops',
        presenceLoader: (_) async => throw StateError('offline'),
      );
      await tester.tap(find.byTooltip('群聊详情'));
      await tester.pumpAndSettle();
      expect(find.text('3 位成员'), findsOneWidget);
      expect(find.textContaining('人在线'), findsNothing);
    },
  );

  for (final accountChanged in [false, true]) {
    testWidgets(
      'pending member reload retains only same-account rows: $accountChanged',
      (tester) async {
        Completer<ImMemberPage>? pending;
        final page = ImMemberPage(
          items: PreviewData.conversationMembers('ops'),
          page: 1,
          pageSize: 50,
          total: 3,
        );
        await _pumpChat(
          tester,
          'ops',
          testMemberScope: accountChanged,
          memberPageLoader: (_, _) => pending?.future ?? Future.value(page),
        );
        await tester.tap(find.byTooltip('群聊详情'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看全部'));
        await tester.pumpAndSettle();
        final scope = ProviderScope.containerOf(
          tester.element(find.byKey(const Key('group-member-directory-sheet'))),
        );
        pending = Completer<ImMemberPage>();
        scope.read(_memberTestScopeProvider.notifier).change();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.byKey(const Key('group-member-directory-member-me')),
          accountChanged ? findsNothing : findsOneWidget,
        );
        if (!accountChanged) expect(find.text('状态未知'), findsNWidgets(3));
        pending.complete(page);
        await tester.pumpAndSettle();
      },
    );
  }

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
    expect(
      find.descendant(
        of: receiptAction,
        matching: find.byIcon(Icons.done_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: receiptAction,
        matching: find.byIcon(Icons.done_all_rounded),
      ),
      findsNothing,
    );
    expect(find.text('回执'), findsNothing);
    expect(loadCount, 0);
    final receiptRect = tester.getRect(receiptAction);
    final bubbleTextRect = tester.getRect(find.text('请查收'));
    expect(receiptRect.width, lessThanOrEqualTo(18));
    expect(
      (receiptRect.center.dy - bubbleTextRect.center.dy).abs(),
      lessThan(12),
      reason: '已读状态应与消息气泡保持同一视觉行，不能折到气泡下方',
    );
    expect(
      receiptRect.left,
      greaterThan(bubbleTextRect.right),
      reason: '自己发送的消息应先展示气泡，再在右侧紧跟已读状态',
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

  testWidgets('double check requires positive recipient evidence', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      'ops',
      messages: [
        ImMessage(
          id: 'read-positive',
          conversationId: 'ops',
          sequence: 1,
          senderId: PreviewData.imBootstrap.currentMember.id,
          content: '已确认阅读',
          kind: 'text',
          createdAt: DateTime.utc(2026, 9, 2),
          hasRecipientRead: true,
        ),
      ],
    );
    final action = find.byKey(
      const ValueKey<String>('message-read-receipt-read-positive'),
    );
    expect(
      find.descendant(
        of: action,
        matching: find.byIcon(Icons.done_all_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '已有接收人已读，查看已读详情',
      ),
      findsOneWidget,
    );
    expect(find.text('全部已读'), findsNothing);
  });

  testWidgets(
    'receipt failure and repeated taps do not open duplicate sheets',
    (tester) async {
      final pending = Completer<ImMessageReadReceipt>();
      var loads = 0;
      await _pumpChat(
        tester,
        'direct',
        messages: [
          ImMessage(
            id: 'read-failure',
            conversationId: 'direct',
            sequence: 1,
            senderId: PreviewData.imBootstrap.currentMember.id,
            content: '网络测试',
            kind: 'text',
            createdAt: DateTime.utc(2026, 9, 2),
          ),
        ],
        readReceiptLoader: (_) {
          loads++;
          return pending.future;
        },
      );
      final action = find.byKey(
        const ValueKey<String>('message-read-receipt-read-failure'),
      );
      await tester.tap(action);
      await tester.tap(action);
      expect(loads, 1);
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法获取已读状态，请稍后重试'), findsOneWidget);
      expect(
        find.byKey(const Key('message-read-receipts-sheet')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: action,
          matching: find.byIcon(Icons.done_all_rounded),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('consecutive sender keeps one avatar on the first message', (
    tester,
  ) async {
    final messages = [
      ImMessage(
        id: 'cluster-first',
        conversationId: 'ops',
        sequence: 20,
        senderId: 'member-1',
        content: '第一条连续消息',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 4),
      ),
      ImMessage(
        id: 'cluster-last',
        conversationId: 'ops',
        sequence: 21,
        senderId: 'member-1',
        content: '第二条连续消息',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 4, 2),
      ),
    ];

    await _pumpChat(tester, 'ops', messages: messages);

    expect(
      find.byKey(const ValueKey<String>('message-avatar-cluster-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('message-avatar-cluster-last')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('message-time-cluster-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('message-time-cluster-last')),
      findsOneWidget,
    );
    final firstBubble = tester.widget<Container>(
      find.byKey(const ValueKey<String>('message-bubble-cluster-first')),
    );
    final lastBubble = tester.widget<Container>(
      find.byKey(const ValueKey<String>('message-bubble-cluster-last')),
    );
    final firstRadius =
        (firstBubble.decoration! as BoxDecoration).borderRadius!
            as BorderRadius;
    final lastRadius =
        (lastBubble.decoration! as BoxDecoration).borderRadius! as BorderRadius;
    expect(firstRadius.topLeft, const Radius.circular(4));
    expect(firstRadius.bottomLeft, const Radius.circular(14));
    expect(lastRadius.topLeft, const Radius.circular(14));
    expect(lastRadius.bottomLeft, const Radius.circular(14));
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('message-avatar-cluster-first')),
          )
          .dy,
      tester
          .getTopLeft(
            find.byKey(const ValueKey<String>('message-bubble-cluster-first')),
          )
          .dy,
    );
  });

  testWidgets('same sender starts a new avatar group after a time gap', (
    tester,
  ) async {
    final messages = [
      ImMessage(
        id: 'gap-first',
        conversationId: 'ops',
        sequence: 20,
        senderId: 'member-1',
        content: '上一组消息',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 4),
      ),
      ImMessage(
        id: 'gap-next',
        conversationId: 'ops',
        sequence: 21,
        senderId: 'member-1',
        content: '间隔后的新一组消息',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 4, 6),
      ),
    ];

    await _pumpChat(tester, 'ops', messages: messages);

    expect(
      find.byKey(const ValueKey<String>('message-avatar-gap-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('message-avatar-gap-next')),
      findsOneWidget,
    );
  });

  testWidgets('outgoing messages keep the current member avatar key', (
    tester,
  ) async {
    const currentMember = ImMember(
      id: 'me-with-avatar',
      username: 'term.me',
      displayName: '当前成员',
      isOnline: true,
      avatarKey: 'terminal-manager',
    );
    final source = PreviewData.imBootstrap;
    final bootstrap = ImBootstrap(
      currentMember: currentMember,
      conversations: _chatFixtureBootstrap().conversations,
      contacts: source.contacts,
      permissions: source.permissions,
      config: source.config,
    );
    final outgoing = ImMessage(
      id: 'outgoing-avatar-key',
      conversationId: 'ops',
      sequence: 22,
      senderId: currentMember.id,
      content: '头像 key 不应丢失',
      kind: 'text',
      createdAt: DateTime.utc(2026, 9, 1, 4, 2),
    );

    await _pumpChat(tester, 'ops', bootstrap: bootstrap, messages: [outgoing]);

    final avatar = tester.widget<InitialAvatar>(
      find.byKey(const ValueKey<String>('message-avatar-outgoing-avatar-key')),
    );
    expect(avatar.avatarKey, currentMember.avatarKey);
  });

  testWidgets(
    'group chat falls back to cached members while paging is offline',
    (tester) async {
      const cachedSender = ImMember(
        id: 'cached-group-sender',
        username: 'cached.sender',
        displayName: '缓存成员',
        isOnline: false,
        avatarKey: 'terminal-member',
      );
      final cachedMembers = [
        PreviewData.imBootstrap.currentMember,
        cachedSender,
      ];
      final message = ImMessage(
        id: 'cached-member-avatar',
        conversationId: 'ops',
        sequence: 23,
        senderId: cachedSender.id,
        content: '离线时仍显示缓存头像',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 4, 3),
      );

      await _pumpChat(
        tester,
        'ops',
        messages: [message],
        members: cachedMembers,
        pageMembers: const [],
      );

      final avatar = tester.widget<InitialAvatar>(
        find.byKey(
          const ValueKey<String>('message-avatar-cached-member-avatar'),
        ),
      );
      expect(avatar.name, cachedSender.displayName);
      expect(avatar.avatarKey, cachedSender.avatarKey);
      expect(find.text('2 位成员'), findsOneWidget);
    },
  );

  testWidgets(
    'group messages reuse contact avatars before member paging loads',
    (tester) async {
      const contactSender = ImMember(
        id: 'contact-group-sender',
        username: 'contact.sender',
        displayName: '通讯录成员',
        isOnline: true,
        avatarKey: 'person',
      );
      final source = PreviewData.imBootstrap;
      final bootstrap = ImBootstrap(
        currentMember: source.currentMember,
        conversations: _chatFixtureBootstrap().conversations,
        contacts: const [contactSender],
        permissions: source.permissions,
        config: source.config,
      );
      final message = ImMessage(
        id: 'contact-member-avatar',
        conversationId: 'ops',
        sequence: 24,
        senderId: contactSender.id,
        content: '分页未完成也显示联系人头像',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 1, 4, 4),
      );

      await _pumpChat(
        tester,
        'ops',
        bootstrap: bootstrap,
        messages: [message],
        members: const [],
        pageMembers: const [],
      );

      final avatar = tester.widget<InitialAvatar>(
        find.byKey(
          const ValueKey<String>('message-avatar-contact-member-avatar'),
        ),
      );
      expect(avatar.name, contactSender.displayName);
      expect(avatar.avatarKey, contactSender.avatarKey);
    },
  );

  testWidgets('group chat hides an unknown member count', (tester) async {
    await _pumpChat(tester, 'ops', members: const [], pageMembers: const []);

    expect(find.text('0 位成员'), findsNothing);
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

  testWidgets('empty chat matches desktop and search keeps result copy', (
    tester,
  ) async {
    await _pumpChat(tester, 'tang');

    expect(find.text('发送第一条消息开始协作'), findsOneWidget);
    expect(find.byKey(const Key('chat-empty-start')), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    expect(find.text('没有匹配的消息'), findsNothing);

    await tester.tap(find.byTooltip('搜索聊天记录'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'not-found');
    await tester.pump();

    expect(find.text('发送第一条消息开始协作'), findsNothing);
    expect(find.text('没有匹配的消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('direct chat does not expose cached online state while offline', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      'tang',
      realtimeAvailability: ImRealtimeAvailability.unavailable,
    );

    expect(find.text('状态未知'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
    final avatar = tester.widget<InitialAvatar>(
      find.byType(InitialAvatar).first,
    );
    expect(avatar.online, isNull);
  });

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
    expect(mixed.style?.fontSize, 15);
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

  testWidgets('outgoing media fallback stays readable on the light bubble', (
    tester,
  ) async {
    final message = ImMessage(
      id: 'outgoing-video-fallback',
      conversationId: 'ops',
      sequence: 13,
      senderId: PreviewData.imBootstrap.currentMember.id,
      content: '现场验收.mp4',
      kind: 'video',
      attachments: const [
        ImMessageAttachment(
          id: 'outgoing-video-attachment',
          type: 'video',
          fileName: '现场验收.mp4',
          contentType: 'video/mp4',
          size: 4096,
          sha256: 'outgoing-video-sha256',
          durationSeconds: 18,
        ),
      ],
      createdAt: DateTime(2026, 8, 31, 12, 1),
    );

    await _pumpChat(tester, 'ops', messages: [message]);

    final play = tester.widget<Icon>(find.byIcon(Icons.play_circle_outline));
    expect(play.color, AppColors.primary);
    expect(find.text('现场验收.mp4'), findsNothing);
    expect(find.text('18 秒 · 4.0 KB'), findsOneWidget);
    final metadata = tester.widget<Text>(find.text('18 秒 · 4.0 KB'));
    expect(metadata.style?.color, AppColors.secondaryText);
  });

  testWidgets(
    'audio message uses an inline player instead of an external-open cue',
    (tester) async {
      final message = ImMessage(
        id: 'audio-message',
        conversationId: 'ops',
        sequence: 14,
        senderId: PreviewData.imBootstrap.currentMember.id,
        content: 'AI-UAT-offline-audio.wav',
        kind: 'audio',
        attachments: const [
          ImMessageAttachment(
            id: 'audio-attachment',
            type: 'audio',
            fileName: 'AI-UAT-offline-audio.wav',
            contentType: 'audio/wav',
            size: 88278,
            sha256: 'audio-sha256',
            durationSeconds: 1,
          ),
        ],
        createdAt: DateTime(2026, 9, 2, 3, 44),
      );

      await _pumpChat(tester, 'ops', messages: [message]);

      final player = find.byKey(
        const ValueKey<String>('message-audio-player-audio-attachment'),
      );
      expect(player, findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
      expect(find.text('AI-UAT-offline-audio.wav'), findsOneWidget);
      expect(find.text('0:01 · 86.2 KB'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('message-audio-progress-audio-attachment'),
        ),
        findsOneWidget,
      );
      final semantics = tester.widget<Semantics>(player);
      expect(semantics.properties.label, '播放音频 AI-UAT-offline-audio.wav');
    },
  );

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

    expect(
      find.byKey(const ValueKey<String>('message-pending-local-pending')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('message-retry-local-failed')),
      findsOneWidget,
    );
    expect(find.text('发送中'), findsNothing);
    expect(find.text('发送失败，点此重试'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('发送中，等待确认')), findsOneWidget);
  });

  testWidgets(
    'pending message exposes safe retry sheet, never server actions',
    (tester) async {
      final pending = ImMessage(
        id: 'local-waiting',
        conversationId: 'ops',
        sequence: 0,
        senderId: PreviewData.imBootstrap.currentMember.id,
        clientMessageId: 'stable-client-id',
        content: '待发消息',
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 2),
        localStatus: ImLocalMessageStatus.pending,
        lastError: 'HTTP 500 https://private.invalid/path?token=secret',
      );
      await _pumpChat(tester, 'ops', messages: [pending]);
      await tester.longPress(find.text('待发消息'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
      expect(find.text('等待发送'), findsOneWidget);
      expect(find.text('立即重试'), findsOneWidget);
      expect(find.text('消息服务请求失败（HTTP 500）'), findsOneWidget);
      for (final label in ['编辑', '撤回', '转发', '收藏', '设为群置顶', '查看已读', '删除']) {
        expect(find.text(label), findsNothing);
      }
      expect(find.textContaining('private.invalid'), findsNothing);
      expect(find.textContaining('secret'), findsNothing);
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      expect(find.text('待发消息'), findsOneWidget);
    },
  );

  test('pending status never renders raw historical error details', () {
    ImMessage message(String error) => ImMessage(
      id: 'local-test',
      sequence: 0,
      senderId: 'self',
      content: '',
      kind: 'file',
      createdAt: null,
      localStatus: ImLocalMessageStatus.pending,
      lastError: error,
    );
    expect(
      imOutboxStatusText(message('SocketException token=secret')),
      '尚未收到发送确认，将自动重试',
    );
    expect(imOutboxStatusText(message('网络超时，等待自动重试')), '网络超时，等待自动重试');
    expect(imOutboxStatusText(message('网络不可用，等待自动重试')), '网络不可用，等待自动重试');
    expect(
      imOutboxStatusText(message('消息服务请求失败（HTTP 429）')),
      '消息服务请求失败（HTTP 429）',
    );
    expect(
      imOutboxStatusText(message('视频上传失败（HTTP 500） token=secret')),
      '视频上传失败（HTTP 500）',
    );
  });

  testWidgets('queued image keeps its preview and compact pending clock', (
    tester,
  ) async {
    final pending = ImMessage(
      id: 'local-pending-image',
      conversationId: 'ops',
      sequence: 0,
      senderId: PreviewData.imBootstrap.currentMember.id,
      clientMessageId: 'pending-image',
      content: '',
      kind: 'image',
      images: const [
        ImMessageImage(
          id: 'local-outbox:pending-image:file-token',
          fileName: 'offline.jpg',
          size: 68,
          contentType: 'image/jpeg',
          sha256: 'local-image-sha256',
        ),
      ],
      createdAt: DateTime.utc(2026, 9, 2, 4),
      localStatus: ImLocalMessageStatus.pending,
    );

    await _pumpChat(tester, 'ops', messages: [pending]);

    expect(
      find.byKey(
        const ValueKey<String>(
          'message-image-thumbnail:local-pending-image:local-outbox:pending-image:file-token',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('message-pending-local-pending-image')),
      findsOneWidget,
    );
  });

  for (final firstSequence in [99, 1]) {
    testWidgets(
      'scrolling loads a partial history page beginning at $firstSequence',
      (tester) async {
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
                sequence: firstSequence,
                senderId: 'member-1',
                content: '更早的消息',
                kind: 'text',
                createdAt: DateTime.utc(2026, 8, 31, 7, 59),
              ),
            ];
          },
        );

        expect(find.text('加载更早消息'), findsNothing);
        final list = find.byKey(
          const PageStorageKey<String>('chat-messages:ops'),
        );
        await tester.drag(list, const Offset(0, 1800));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(loadCount, 1);
        expect(requestedBeforeSequence, 100);
        final rememberedWindow = windowMemory.restore('ops');
        expect(rememberedWindow.take, 81);
        expect(rememberedWindow.hasOlder, firstSequence > 1);
      },
    );
  }

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

  testWidgets('history can retry from the clamped top without reversing direction', (
    tester,
  ) async {
    final messages = List<ImMessage>.generate(30, (index) => ImMessage(
      id: 'edge-history-$index',
      conversationId: 'ops',
      sequence: index + 100,
      senderId: 'member-1',
      content: 'Edge history $index',
      kind: 'text',
      createdAt: DateTime.utc(2026, 9, 3, 0, index),
    ));
    final firstLoad = Completer<List<ImMessage>>();
    var loads = 0;
    await _pumpChat(tester, 'ops', messages: messages,
      olderMessageLoader: (_, {beforeSequence}) {
        loads++;
        return loads == 1 ? firstLoad.future : Future.value(<ImMessage>[]);
      },
    );
    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    await tester.drag(list, const Offset(0, 5000));
    await tester.pump();
    final controller = tester.widget<ListView>(list).controller!;
    expect(loads, 1);
    // More gestures while the request is pending must not duplicate it.
    await tester.drag(list, const Offset(0, 300));
    await tester.pump();
    expect(loads, 1);
    expect(controller.offset, controller.position.minScrollExtent);
    firstLoad.completeError(StateError('temporary history failure'));
    await tester.pumpAndSettle();
    // Still at the top: Android clamping emits overscroll, not a pixel change.
    await tester.drag(list, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(loads, 2);
    await tester.drag(list, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(loads, 2, reason: 'an exhausted page must not be requested again');
  });

  testWidgets('successive upward gestures reach message one in a 510 message chat', (
    tester,
  ) async {
    final all = List<ImMessage>.generate(510, (index) => ImMessage(
      id: 'batch-history-${index + 1}',
      conversationId: 'ops',
      sequence: index + 1,
      senderId: 'member-1',
      content: 'Batch history ${index + 1}',
      kind: 'text',
      createdAt: DateTime.utc(2026, 9, 3, 0, 0, index),
    ));
    final cursors = <int>[];
    final memory = ConversationMessageWindowMemory();
    await _pumpChat(tester, 'ops', useRealMessageWindow: true,
      messageWindowMemory: memory,
      messageWindowLoader: (_, {take}) async => all.sublist(
        (all.length - (take ?? 80)).clamp(0, all.length),
      ),
      olderMessageLoader: (_, {beforeSequence}) async {
        cursors.add(beforeSequence!);
        final end = beforeSequence - 1;
        return all.sublist((end - 80).clamp(0, end), end);
      },
    );
    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    for (var attempt = 0; attempt < 12; attempt++) {
      await tester.drag(list, const Offset(0, 30000));
      await tester.pumpAndSettle();
    }
    expect(cursors, [431, 351, 271, 191, 111, 31]);
    expect(memory.restore('ops').take, 510);
    expect(memory.restore('ops').hasOlder, isFalse);
    expect(find.text('Batch history 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final first in [1, 151]) {
    testWidgets('first unread $first is visible without marking the latest backlog', (tester) async {
      final all = _unreadMessages(510);
      final reads = <int>[];
      final slices = <int>[];
      await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(first - 1, 510),
        messages: all.sublist(430),
        anchoredWindowLoader: (_, {required take, required beforeSequence}) async {
          slices.add(beforeSequence);
          return all.where((item) => item.sequence < beforeSequence).toList().reversed.take(take).toList().reversed.toList();
        },
        markVisibleRead: (_, sequence) async { reads.add(sequence); },
      );
      final firstBubble = find.byKey(ValueKey('message-bubble-unread-$first'));
      expect(firstBubble, findsOneWidget);
      final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
      expect(tester.getRect(list).overlaps(tester.getRect(firstBubble)), isTrue);
      expect(find.byKey(const Key('chat-unread-positioning')), findsNothing);
      expect(find.byKey(const Key('chat-first-unread-marker')), findsOneWidget);
      expect(slices, [first + 40]);
      expect(reads, isNotEmpty);
      expect(reads.every((value) => value >= first && value < first + 39), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('first unread keeps mixed short history and long new messages anchored on a phone', (tester) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final all = List.generate(610, (index) => ImMessage(
      id: 'mixed-${index+1}', conversationId: 'ops', sequence: index+1,
      senderId: 'member-1', kind: 'text',
      content: index < 510 ? 'AI-UAT-701-BATCH-${(index+1).toString().padLeft(4,'0')}' :
        'AI-UAT-20260903-094154-UNREAD-${(index-509).toString().padLeft(4,'0')}',
      createdAt: index < 510 ? DateTime.utc(2026,9,3,0,0,index) : DateTime.utc(2026,9,3,1,41,index),
    ));
    final reads = <int>[];
    await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(510,610),
      initialConversation: _unreadBootstrap(510,610).conversations.single,
      messages: all.sublist(530), enablePresence: true,
      latestReconciler: (_) async => true,
      anchoredWindowLoader: (_, {required take, required beforeSequence}) async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return _sliceMessages(all,take,beforeSequence);
      },
      markVisibleRead: (_, sequence) async { reads.add(sequence); });
    final bubble=find.byKey(const Key('message-bubble-mixed-511'));
    expect(bubble,findsOneWidget);
    expect(bubble.hitTestable(), findsOneWidget);
    expect(reads.last, inInclusiveRange(511, 530));
    final container=ProviderScope.containerOf(tester.element(find.byType(ChatPage)));
    container.invalidate(conversationMessageRevisionProvider('ops'));
    await tester.pump();
    // A retained, stable layout has no animation to keep pumpAndSettle waiting.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(bubble.hitTestable(),findsOneWidget);
    expect(reads.last, inInclusiveRange(511,530));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first unread never retains old-account messages while replacement data is pending', (tester) async {
    final all = _unreadMessages(210);
    final pending = Completer<List<ImMessage>>();
    var replacement = false;
    await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(100,210), testMemberScope: true,
      anchoredWindowLoader: (_, {required take, required beforeSequence}) => replacement
          ? pending.future : Future.value(_sliceMessages(all,take,beforeSequence)));
    expect(find.byKey(const Key('message-bubble-unread-101')),findsOneWidget);
    replacement = true;
    final container = ProviderScope.containerOf(tester.element(find.byType(ChatPage)));
    container.read(_memberTestScopeProvider.notifier).change();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('message-bubble-unread-101')),findsNothing);
    pending.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-bubble-unread-101')),findsNothing);
  });

  testWidgets('first unread waits for its slice and can explicitly return to latest', (tester) async {
    final slice = Completer<List<ImMessage>>();
    final all = _unreadMessages(120);
    final reads = <int>[];
    await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(0,120), messages: all.sublist(40),
      settle:false, anchoredWindowLoader: (_, {required take, required beforeSequence}) => slice.future,
      markVisibleRead: (_, sequence) async {reads.add(sequence);});
    await tester.pump(const Duration(milliseconds:200));
    expect(reads,isEmpty);
    await tester.tap(find.byKey(const Key('chat-return-latest')));
    await tester.pumpAndSettle();
    expect(reads.last,120);
    slice.complete(all.take(40).toList());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-first-unread-marker')),findsNothing);
    expect(reads.last,120,reason:'late anchor completion cannot move/read the old slice');
  });

  testWidgets('first unread forward paging preserves position and never skips to page end', (tester) async {
    final all=_unreadMessages(210);
    final reads=<int>[];
    final slices=<int>[];
    await _pumpChat(tester,'ops',bootstrap:_unreadBootstrap(0,210),messages:all.sublist(130),
      anchoredWindowLoader: (_, {required take, required beforeSequence}) async {
        slices.add(beforeSequence);
        return all.where((item)=>item.sequence<beforeSequence).toList().reversed.take(take).toList().reversed.toList();
      },markVisibleRead:(_,sequence)async{reads.add(sequence);});
    final list=find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    final controller=tester.widget<ListView>(list).controller!;
    await tester.drag(list,const Offset(0,-5000));
    await tester.pumpAndSettle();
    expect(slices,contains(121));
    expect(reads.every((sequence)=>sequence<120),isTrue,
      reason:'appending page 41-120 must not jump to 120 and mark it read');
    expect(controller.offset,lessThan(controller.position.maxScrollExtent-100));
    for(var count=0;count<12;count++){
      await tester.drag(list,const Offset(0,-1600));await tester.pumpAndSettle();
      if(reads.contains(210))break;
    }
    expect(reads.last,210);
    expect(find.byKey(const Key('chat-unread-positioning')),findsNothing);
  });

  testWidgets('first unread follows a cross-device read while the initial slice is pending', (tester) async {
    final all = _unreadMessages(210);
    final oldSlice = Completer<List<ImMessage>>();
    var current = _unreadBootstrap(0, 210);
    final reads = <int>[];
    await _pumpChat(tester, 'ops', bootstrapLoader: () async => current,
      messages: all.sublist(130), settle: false,
      anchoredWindowLoader: (_, {required take, required beforeSequence}) =>
        beforeSequence == 41 ? oldSlice.future : Future.value(_sliceMessages(all, take, beforeSequence)),
      markVisibleRead: (_, sequence) async { reads.add(sequence); });
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, isEmpty);
    current = _unreadBootstrap(100, 210);
    final scope = ProviderScope.containerOf(tester.element(find.byType(ChatPage)));
    scope.invalidate(imBootstrapProvider);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-bubble-unread-101')), findsOneWidget);
    expect(reads.last, inInclusiveRange(101, 139));
    oldSlice.complete(all.take(40).toList());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-bubble-unread-101')), findsOneWidget);
    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    final offset = tester.widget<ListView>(list).controller!.offset;
    current = _unreadBootstrap(210, 210);
    scope.invalidate(imBootstrapProvider);
    await tester.pumpAndSettle();
    expect(tester.widget<ListView>(list).controller!.offset, closeTo(offset, 1),
      reason: 'a later desktop read must not move an already positioned reader');
  });

  testWidgets('first unread forward failure retries only on a new gesture and ignores canceled results', (tester) async {
    final all = _unreadMessages(210);
    final page = Completer<List<ImMessage>>();
    var calls = 0;
    await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(0, 210),
      messages: all.sublist(130),
      anchoredWindowLoader: (_, {required take, required beforeSequence}) async {
        if (beforeSequence == 121) {
          calls++;
          if (calls == 1) throw StateError('synthetic network interruption');
          return page.future;
        }
        return _sliceMessages(all, take, beforeSequence);
      });
    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    await tester.drag(list, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('消息加载失败，请再次上滑重试'), findsOneWidget);
    await tester.drag(list, const Offset(0, -400));
    await tester.pump();
    await tester.drag(list, const Offset(0, -400));
    await tester.pump();
    expect(calls, 2, reason: 'pending forward pages must be coalesced');
    await tester.tap(find.byKey(const Key('chat-return-latest')));
    await tester.pumpAndSettle();
    page.completeError(StateError('late canceled request'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-return-latest')), findsNothing);
    expect(find.byKey(const Key('message-bubble-unread-210')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first unread positions variable height messages at large text scale', (tester) async {
    final all = _unreadMessages(210).map((item) => ImMessage(
      id: item.id, conversationId: item.conversationId, sequence: item.sequence,
      senderId: item.senderId, kind: 'text', createdAt: item.createdAt,
      content: item.sequence % 3 == 0 ? '${item.content}\n${List.filled(8, '多行正文').join('\n')}' : item.content,
    )).toList();
    final reads = <int>[];
    await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(150, 210),
      messages: all.sublist(130),
      wrapChat: (child) => MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(1.5)), child: child),
      anchoredWindowLoader: (_, {required take, required beforeSequence}) async => _sliceMessages(all, take, beforeSequence),
      markVisibleRead: (_, sequence) async { reads.add(sequence); });
    final list = find.byKey(const PageStorageKey<String>('chat-messages:ops'));
    final bubble = find.byKey(const Key('message-bubble-unread-151'));
    expect(bubble, findsOneWidget);
    expect(tester.getRect(list).overlaps(tester.getRect(bubble)), isTrue);
    expect(reads.last, inInclusiveRange(151, 160));
    expect(find.text('重试定位未读消息'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first unread does not mark a cached latest window when bootstrap fails', (tester) async {
    final all = _unreadMessages(210);
    final reads = <int>[];
    var offline = true;
    await _pumpChat(tester, 'ops', messages: all.sublist(130),
      bootstrapLoader: () async {
        if (offline) throw StateError('synthetic bootstrap failure');
        return _unreadBootstrap(100, 210);
      },
      anchoredWindowLoader: (_, {required take, required beforeSequence}) async => _sliceMessages(all, take, beforeSequence),
      markVisibleRead: (_, sequence) async { reads.add(sequence); });
    expect(reads, isEmpty);
    offline = false;
    ProviderScope.containerOf(tester.element(find.byType(ChatPage))).invalidate(imBootstrapProvider);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-bubble-unread-101')), findsOneWidget);
    expect(reads.last, inInclusiveRange(101, 139));
  });

  for (final hiddenMode in ['background', 'offstage']) {
    testWidgets('first unread waits for actual visibility after $hiddenMode loading', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final all = _unreadMessages(210);
      final pending = Completer<List<ImMessage>>();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final reads = <int>[];
      await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(100, 210), settle: false,
        anchoredWindowLoader: (_, {required take, required beforeSequence}) => pending.future,
        markVisibleRead: (_, sequence) async { reads.add(sequence); },
        wrapChat: (child) => ValueListenableBuilder<bool>(valueListenable: visible,
          child: child, builder: (_, value, child) => TickerMode(enabled: value,
            child: Offstage(offstage: !value, child: child))),
      );
      await tester.pump();
      if (hiddenMode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else { visible.value = false; }
      pending.complete(_sliceMessages(all, 80, 141));
      await tester.pumpAndSettle();
      expect(reads, isEmpty);
      if (hiddenMode == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else { visible.value = true; }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-bubble-unread-101')), findsOneWidget);
      expect(reads.last, inInclusiveRange(101, 139));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('first unread skips deleted sequences but not the remaining unread backlog', (tester) async {
    final all = _unreadMessages(210).where((item) => item.sequence < 151 || item.sequence > 160).toList();
    final reads = <int>[];
    await _pumpChat(tester, 'ops', bootstrap: _unreadBootstrap(150, 210),
      messages: all.sublist(all.length - 80),
      anchoredWindowLoader: (_, {required take, required beforeSequence}) async => _sliceMessages(all, take, beforeSequence),
      markVisibleRead: (_, sequence) async { reads.add(sequence); });
    expect(find.byKey(const Key('message-bubble-unread-161')), findsOneWidget);
    expect(reads.last, inInclusiveRange(161, 180));
    expect(find.byKey(const Key('chat-first-unread-marker')), findsOneWidget);
  });

  testWidgets('first unread slice failure stays unread until explicit retry succeeds', (tester) async {
    final all=_unreadMessages(120);var fail=true;final reads=<int>[];
    await _pumpChat(tester,'ops',bootstrap:_unreadBootstrap(0,120),messages:all.sublist(40),
      anchoredWindowLoader:(_, {required take, required beforeSequence}) async {
        if(fail)throw StateError('synthetic offline');
        return all.take(40).toList();
      },markVisibleRead:(_,sequence)async{reads.add(sequence);});
    expect(reads,isEmpty);expect(find.text('消息加载失败'),findsOneWidget);
    fail=false;
    final scope=ProviderScope.containerOf(tester.element(find.byType(ChatPage)));
    scope.invalidate(conversationAnchoredWindowProvider((conversationId:'ops',take:80,beforeSequence:41)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-bubble-unread-1')),findsOneWidget);
    expect(reads.last,lessThan(40));
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

List<ImMessage> _unreadMessages(int total) => List.generate(total,(index)=>ImMessage(
  id:'unread-${index+1}',conversationId:'ops',sequence:index+1,senderId:'member-1',
  content:'Unread message ${index+1}',kind:'text',createdAt:DateTime.utc(2026,9,3,0,0,index)));

List<ImMessage> _sliceMessages(List<ImMessage> all, int take, int before) =>
  all.where((item) => item.sequence < before).toList().reversed.take(take).toList().reversed.toList();

ImBootstrap _unreadBootstrap(int read,int latest) => ImBootstrap(
  currentMember:PreviewData.imBootstrap.currentMember,contacts:PreviewData.imBootstrap.contacts,
  conversations:[ImConversation(id:'ops',type:'group',title:'Unread fixture',preview:'',
    updatedAt:DateTime.utc(2026,9,3),unreadCount:latest-read,lastReadSequence:read,lastMessageSequence:latest)],
);

// Geometry, paging and receipt tests supply their own message sequences. The
// product preview's unread counters do not describe those synthetic messages.
ImBootstrap _chatFixtureBootstrap() {
  final source = PreviewData.imBootstrap;
  return ImBootstrap(
    currentMember: source.currentMember,
    contacts: source.contacts,
    permissions: source.permissions,
    config: source.config,
    conversations: source.conversations.map((item) => ImConversation(
      id: item.id, type: item.type, title: item.title, preview: item.preview,
      updatedAt: item.updatedAt, unreadCount: 0,
    )).toList(),
  );
}

Future<void> _pumpChat(
  WidgetTester tester,
  String conversationId, {
  List<ImMessage> messages = const [],
  ImRepository? repository,
  ImBootstrap? bootstrap,
  Future<ImBootstrap> Function()? bootstrapLoader,
  ImConversation? initialConversation,
  List<ImMember>? members,
  List<ImMember>? pageMembers,
  ImGroupProfile? groupProfile,
  Future<ImGroupProfile?> Function(String conversationId)? groupProfileLoader,
  Uint8List? videoPreview,
  ConversationOlderMessageLoader? olderMessageLoader,
  ConversationMessageWindowLoader? messageWindowLoader,
  ConversationAnchoredWindowLoader? anchoredWindowLoader,
  ConversationMessageWindowMemory? messageWindowMemory,
  ValueChanged<int>? onWindowRequested,
  ValueChanged<String>? onFullMembersRequested,
  ValueChanged<String>? onMemberPageRequested,
  Future<ImMemberPage> Function(int page, String keyword)? memberPageLoader,
  Future<ImConversationPresence> Function(String id)? presenceLoader,
  bool testMemberScope = false,
  ImMessageReadReceiptLoader? readReceiptLoader,
  ImRealtimeAvailability realtimeAvailability =
      ImRealtimeAvailability.available,
  bool settle = true,
  bool openFromLauncher = false,
  bool useRealMessageWindow = false,
  bool enablePresence = false,
  Future<void> Function(String, int)? markVisibleRead,
  Future<void> Function(String)? enterPresence,
  ConversationLatestReconciler? latestReconciler,
  Widget Function(Widget)? wrapChat,
  bool liveMemberFixtures = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (repository != null) imRepositoryProvider.overrideWithValue(repository),
        if (repository != null) imSyncCoordinatorProvider.overrideWith((ref) => ImSyncCoordinator(
          repository,
          availabilityController: ref.read(imRealtimeAvailabilityControllerProvider.notifier),
          onChanged: (_) {},
        )),
        if (liveMemberFixtures)
          imMemberPresenceProjectionProvider.overrideWith(() => FixtureMemberPresence([
            (bootstrap ?? PreviewData.imBootstrap).currentMember,
            ...(bootstrap ?? PreviewData.imBootstrap).contacts,
            ...(members ?? PreviewData.conversationMembers(conversationId)),
            ...?pageMembers,
          ])),
        conversationVisibleReadMarkerProvider.overrideWithValue(
          markVisibleRead ?? (id, sequence) async {},
        ),
        conversationPresenceEnterActionProvider.overrideWithValue(
          enterPresence ?? (id) async {},
        ),
        conversationPresenceLeaveActionProvider.overrideWithValue(() async {}),
        if (latestReconciler != null) ...[
          conversationLatestReconcilerProvider.overrideWithValue(latestReconciler),
          conversationLatestReconcileCoordinatorProvider.overrideWithValue(
            ConversationLatestReconcileCoordinator(minimumInterval: Duration.zero),
          ),
        ],
        if (testMemberScope)
          collaborationAccountScopeProvider.overrideWith(
            (ref) => ref.watch(_memberTestScopeProvider),
          )
        else
          collaborationAccountScopeProvider.overrideWithValue(''),
        imRealtimeAvailabilityProvider.overrideWithValue(realtimeAvailability),
        imBootstrapProvider.overrideWith(
          (ref) async => bootstrapLoader?.call() ?? bootstrap ?? _chatFixtureBootstrap(),
        ),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        conversationMessagesProvider.overrideWith((ref, id) async => messages),
        if (anchoredWindowLoader != null)
          conversationAnchoredWindowLoaderProvider.overrideWithValue(anchoredWindowLoader),
        if (useRealMessageWindow)
          conversationMessageWindowLoaderProvider.overrideWithValue((
            id, {
            take,
          }) async {
            onWindowRequested?.call(take ?? 80);
            return messageWindowLoader?.call(id, take: take) ?? messages;
          })
        else
          conversationMessageWindowProvider.overrideWith((ref, key) async {
            onWindowRequested?.call(key.take);
            return messageWindowLoader?.call(
                  key.conversationId,
                  take: key.take,
                ) ??
                messages;
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
        conversationCachedMembersProvider.overrideWith(
          (ref, id) async => members ?? PreviewData.conversationMembers(id),
        ),
        conversationMemberPageProvider.overrideWith((ref, key) async {
          ref.watch(_memberTestScopeProvider);
          onMemberPageRequested?.call(key.keyword);
          if (memberPageLoader != null) {
            return memberPageLoader(key.page, key.keyword);
          }
          final source =
              pageMembers ??
              members ??
              PreviewData.conversationMembers(key.conversationId);
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
        conversationPresenceProvider.overrideWith((ref, id) async {
          if (presenceLoader != null) return presenceLoader(id);
          final source =
              pageMembers ?? members ?? PreviewData.conversationMembers(id);
          return ImConversationPresence(
            conversationId: id,
            type: id == 'ops' ? 'group' : 'direct',
            onlineMemberCount: source.where((member) => member.isOnline).length,
            peerOnline: false,
          );
        }),
        groupManagersProvider.overrideWith(
          (ref, id) async => PreviewData.groupManagers(id),
        ),
      ],
      child: MaterialApp(
        home: openFromLauncher
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ChatPage(
                          conversationId: conversationId,
                          enablePresence: false,
                        ),
                      ),
                    ),
                    child: const Text('打开测试会话'),
                  ),
                ),
              )
            : (wrapChat ?? (child) => child)(
                ChatPage(conversationId: conversationId, enablePresence: enablePresence,
                  initialConversation: initialConversation),
              ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _finishComposer(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 10));
    if (tester.widget<IconButton>(find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '发送',
    )).onPressed != null) {
      await tester.pump(const Duration(milliseconds: 150));
      return;
    }
  }
  fail('Local composer transaction did not finish');
}

Future<void> _waitForComposerWrite(WidgetTester tester, ChatComposerFixture fixture) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    if (fixture.cipher.entered.isCompleted) return;
  }
  fixture.cipher.release();
  fail('Composer did not reach SQLite encryption boundary');
}

final Uint8List _testImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

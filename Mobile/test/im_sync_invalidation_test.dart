import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  test('IM realtime availability starts connecting and follows transport', () {
    final container = ProviderContainer.test();
    final controller = container.read(
      imRealtimeAvailabilityControllerProvider.notifier,
    );

    expect(
      container.read(imRealtimeAvailabilityProvider),
      ImRealtimeAvailability.connecting,
      reason: '同步链路尚未证明健康前不能先显示实时可用',
    );
    controller.markAvailable();
    expect(
      container.read(imRealtimeAvailabilityProvider),
      ImRealtimeAvailability.available,
    );
    controller.markUnavailable();
    expect(
      container.read(imRealtimeAvailabilityProvider),
      ImRealtimeAvailability.unavailable,
    );

    container.dispose();
  });

  test('IM sync classifies invalidation by event type and conversation', () {
    final events = <ImSyncEvent>[
      _event(1, 'message.created', 'direct-a'),
      _event(2, 'message.recalled', 'group-b'),
      _event(3, 'group.member.joined', 'group-b'),
      _event(4, 'group.notice.updated', 'group-c'),
      _event(5, 'presence.changed', 'direct-d'),
      const ImSyncEvent(
        sequence: 6,
        id: 'event-6',
        type: 'message.created',
        payloadJson: '{invalid-json',
        createdAt: null,
      ),
    ];

    final result = ImSyncPullResult.fromEvents(
      latestSequence: 6,
      events: events,
    );

    expect(result.changed, isTrue);
    expect(result.latestSequence, 6);
    expect(result.conversationIds, {
      'direct-a',
      'group-b',
      'group-c',
      'direct-d',
    });
    expect(result.messageConversationIds, {'direct-a', 'group-b'});
    expect(result.memberConversationIds, {'group-b'});
    expect(result.groupProfileConversationIds, {'group-c'});
  });

  test(
    'conversation revision only rebuilds the affected conversation',
    () async {
      final builds = <String, int>{};
      final probeProvider = Provider.family<int, String>((ref, conversationId) {
        ref.watch(conversationMessageRevisionProvider(conversationId));
        return builds.update(
          conversationId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      });
      final container = ProviderContainer.test();
      final directSubscription = container.listen(
        probeProvider('direct-a'),
        (_, _) {},
        fireImmediately: true,
      );
      final groupSubscription = container.listen(
        probeProvider('group-b'),
        (_, _) {},
        fireImmediately: true,
      );

      expect(container.read(probeProvider('direct-a')), 1);
      expect(container.read(probeProvider('group-b')), 1);

      container.invalidate(conversationMessageRevisionProvider('direct-a'));
      await container.pump();

      expect(container.read(probeProvider('direct-a')), 2);
      expect(container.read(probeProvider('group-b')), 1);

      directSubscription.close();
      groupSubscription.close();
      container.dispose();
    },
  );

  test('reopening a conversation reuses its retained message window', () async {
    var loadCount = 0;
    final container = ProviderContainer.test(
      overrides: [
        conversationMessageWindowLoaderProvider.overrideWithValue((
          conversationId, {
          take,
        }) async {
          loadCount += 1;
          return const <ImMessage>[];
        }),
      ],
    );
    const key = (conversationId: 'direct-a', take: 80);

    final first = container.listen(
      conversationMessageWindowProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    await container.pump();
    expect(loadCount, 1);
    first.close();
    await container.pump();

    final reopened = container.listen(
      conversationMessageWindowProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    await container.pump();
    expect(loadCount, 1, reason: '热会话保留期内不应重新读取消息窗口');

    container.invalidate(conversationMessageRevisionProvider('group-b'));
    await container.pump();
    expect(loadCount, 1, reason: '其他会话事件不应重建当前消息窗口');

    container.invalidate(conversationMessageRevisionProvider('direct-a'));
    await container.pump();
    expect(loadCount, 2, reason: '当前会话收到事件后才允许精确刷新');

    reopened.close();
    container.dispose();
  });

  test('bounded reconciliation only invalidates a changed server window', () {
    final cached = ImMessage(
      id: 'message-1',
      conversationId: 'group-a',
      sequence: 7,
      senderId: 'member-1',
      clientMessageId: 'client-1',
      content: '已缓存消息',
      kind: 'text',
      createdAt: DateTime.utc(2026, 8, 31, 8),
    );
    final identical = ImMessage.fromJson({
      'id': 'message-1',
      'conversationId': 'group-a',
      'sequence': 7,
      'senderId': 'member-1',
      'clientMessageId': 'client-1',
      'content': '已缓存消息',
      'kind': 'text',
      'createdAt': '2026-08-31T08:00:00Z',
    });
    final secondDeviceMessage = ImMessage(
      id: 'message-2',
      conversationId: 'group-a',
      sequence: 8,
      senderId: 'member-1',
      clientMessageId: 'client-2',
      content: '另一台设备发出的消息',
      kind: 'text',
      createdAt: DateTime.utc(2026, 8, 31, 8, 1),
    );

    expect(imMessageSnapshotsDiffer([cached], [identical]), isFalse);
    expect(
      imMessageSnapshotsDiffer([cached], [identical, secondDeviceMessage]),
      isTrue,
    );
    expect(
      imMessageSnapshotsDiffer(
        [cached],
        [cached.copyWith(recalledAt: DateTime.utc(2026, 8, 31, 8, 2))],
      ),
      isTrue,
    );
  });

  test('badge mismatch detects a missed conversation event', () {
    const currentMember = ImMember(
      id: 'member-me',
      username: 'term.me',
      displayName: '当前成员',
      isOnline: true,
    );
    final bootstrap = ImBootstrap(
      currentMember: currentMember,
      conversations: [
        ImConversation(
          id: 'group-a',
          type: 'group',
          title: '群聊',
          preview: '旧消息',
          updatedAt: DateTime.utc(2026, 9, 1, 4),
          unreadCount: 1,
        ),
        ImConversation(
          id: 'direct-a',
          type: 'direct',
          title: '单聊',
          preview: '',
          updatedAt: DateTime.utc(2026, 9, 1, 4),
          unreadCount: 2,
        ),
      ],
      contacts: const [],
    );

    expect(
      imUnreadProjectionDiffers(
        const ImBadgeSummary(unreadMessages: 3, pendingFriendRequests: 0),
        bootstrap,
      ),
      isFalse,
    );
    expect(
      imUnreadProjectionDiffers(
        const ImBadgeSummary(unreadMessages: 4, pendingFriendRequests: 0),
        bootstrap,
      ),
      isTrue,
    );
    expect(
      imUnreadProjectionDiffers(
        const ImBadgeSummary(unreadMessages: 0, pendingFriendRequests: 0),
        null,
      ),
      isTrue,
    );
  });
}

ImSyncEvent _event(int sequence, String type, String conversationId) =>
    ImSyncEvent(
      sequence: sequence,
      id: 'event-$sequence',
      type: type,
      payloadJson: jsonEncode({'conversationId': conversationId}),
      createdAt: null,
    );

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/im_sync_coordinator.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'background sync persists missing body without opening any chat',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final writes = <String>[];
      server.listen((request) async {
        if (request.method != 'GET') writes.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        final payload = switch (request.uri.path) {
          '/api/im/bootstrap' => {
            'currentMember': {
              'id': 'member',
              'userName': 'test',
              'displayName': 'Test',
            },
            'contacts': [],
            'conversations': [
              {
                'id': 'group',
                'type': 'group',
                'title': 'Group',
                'lastMessageSequence': 85,
                'lastReadSequence': 84,
                'unreadCount': 1,
                'unreadMentionSequences': [85],
              },
            ],
          },
          '/api/im/sync/events' => {'events': [], 'latestSequence': 0},
          '/api/im/badges' => {'unreadMessages': 1, 'pendingFriendRequests': 0},
          '/api/im/conversations' => [
            {
              'id': 'group',
              'type': 'group',
              'title': 'Group',
              'lastMessageSequence': 85,
              'lastReadSequence': 84,
              'unreadCount': 1,
              'unreadMentionSequences': [85],
            },
          ],
          '/api/im/conversations/group/messages' => [_messageJson(85)],
          _ => {},
        };
        request.response.write(jsonEncode(payload));
        await request.response.close();
      });
      FlutterSecureStorage.setMockInitialValues({});
      final sessions = SecureSessionStore();
      await sessions.saveSession(
        MobileSession(
          accessToken: 'local-test-token',
          deviceId: 'device',
          userId: 'account',
          displayName: 'Test',
          username: 'test',
          policySignatureKey: '',
          imApiUrl: 'http://127.0.0.1:${server.port}',
          oaApiUrl: '',
        ),
      );
      final store = _store(inMemoryDatabasePath);
      addTearDown(store.close);
      await store.mergeMessages('account', 'group', [_message(84)]);
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final repaired = Completer<void>();
      final coordinator = ImSyncCoordinator(
        ImRepository(CollaborationClient(sessions), sessions, store),
        availabilityController: container.read(
          imRealtimeAvailabilityControllerProvider.notifier,
        ),
        onChanged: (change) {
          if (change.messageConversationIds.contains('group') &&
              !repaired.isCompleted) {
            repaired.complete();
          }
        },
      );
      try {
        await coordinator.start();
        await repaired.future.timeout(const Duration(seconds: 5));
      } finally {
        await coordinator.stop();
      }
      expect(
        (await store.readMessages('account', 'group')).map((m) => m.sequence),
        [84, 85],
      );
      final group = (await store.readBootstrap('account'))!
          .conversations
          .single;
      expect(group.lastReadSequence, 84);
      expect(group.unreadCount, 1);
      expect(group.unreadMentionSequences, [85]);
      expect(await store.lastEventSequence('account', 'device'), 0);
      expect(
        writes,
        isEmpty,
        reason: 'History repair must never fake read or event ACK',
      );
    },
  );

  test(
    'announced message gap survives restart and commits only with body',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'im-history-gap-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/im.db';
      var store = _store(path);
      await store.mergeMessages('account', 'group', [_message(84)]);
      await store.replaceBootstrap('account', _bootstrap(85));
      final job = (await store.pendingHistoryCatchups('account')).single;
      expect(
        (job.afterSequence, job.beforeSequence, job.targetSequence),
        (84, 86, 85),
      );
      await store.close();

      store = _store(path);
      expect(
        (await store.pendingHistoryCatchups('account')).single.targetSequence,
        85,
      );
      expect(
        await store.commitHistoryCatchupPage(
          'account',
          job,
          const [],
          nextBeforeSequence: 86,
          complete: false,
        ),
        isTrue,
      );
      expect(await store.pendingHistoryCatchups('account'), hasLength(1));
      expect(
        await store.commitHistoryCatchupPage(
          'account',
          job,
          [_message(85)],
          nextBeforeSequence: 85,
          complete: true,
        ),
        isTrue,
      );
      expect(
        (await store.readMessages(
          'account',
          'group',
        )).map((item) => item.sequence),
        [84, 85],
      );
      expect(await store.pendingHistoryCatchups('account'), isEmpty);
      await store.close();
    },
  );

  test(
    'bounded repair persists page progress and preserves read projection',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <int>[];
      server.listen((request) async {
        final before = int.parse(
          request.uri.queryParameters['beforeSequence']!,
        );
        requests.add(before);
        final from = (before - 50).clamp(85, 135);
        final to = (before - 1).clamp(85, 184);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            for (var sequence = from; sequence <= to; sequence++)
              _messageJson(sequence),
          ]),
        );
        await request.response.close();
      });
      FlutterSecureStorage.setMockInitialValues({});
      final sessions = SecureSessionStore();
      await sessions.saveSession(
        MobileSession(
          accessToken: 'token',
          deviceId: 'device',
          userId: 'account',
          displayName: 'Test',
          username: 'test',
          policySignatureKey: '',
          imApiUrl: 'http://127.0.0.1:${server.port}',
          oaApiUrl: '',
        ),
      );
      final store = _store(inMemoryDatabasePath);
      addTearDown(store.close);
      await store.mergeMessages('account', 'group', [_message(84)]);
      await store.replaceBootstrap('account', _bootstrap(184));
      final repository = ImRepository(
        CollaborationClient(sessions),
        sessions,
        store,
      );

      final first = await repository.repairAnnouncedMessageGaps(pageBudget: 1);
      expect(first.changed, {'group'});
      expect(first.progressed, isTrue);
      expect(requests, [185]);
      expect(
        (await store.pendingHistoryCatchups('account')).single.beforeSequence,
        135,
      );
      expect(
        (await store.readBootstrap('account'))!
            .conversations
            .single
            .lastReadSequence,
        80,
      );
      final second = await repository.repairAnnouncedMessageGaps(pageBudget: 1);
      expect(second.changed, {'group'});
      expect(requests, [185, 135]);
      expect(await store.pendingHistoryCatchups('account'), isEmpty);
      final messages = await store.readMessages('account', 'group');
      expect(
        messages.map((item) => item.sequence),
        List.generate(101, (i) => i + 84),
      );
      expect(
        (await store.readBootstrap('account'))!
            .conversations
            .single
            .unreadCount,
        104,
      );
    },
  );
  test(
    'new announcements during repair preserve both ranges and event cursors',
    () async {
      final store = _store(inMemoryDatabasePath);
      addTearDown(store.close);
      await store.mergeMessages('account', 'group', [_message(84)]);
      await store.replaceBootstrap('account', _bootstrap(85));
      final first = (await store.pendingHistoryCatchups('account')).single;
      await store.replaceBootstrap('account', _bootstrap(87));
      await store.commitHistoryCatchupPage(
        'account',
        first,
        [_message(85)],
        nextBeforeSequence: 85,
        complete: true,
      );
      final second = (await store.pendingHistoryCatchups('account')).single;
      expect(
        (second.afterSequence, second.beforeSequence, second.targetSequence),
        (85, 88, 87),
      );
      expect(
        await store.commitHistoryCatchupPage(
          'account',
          first,
          [_message(86)],
          nextBeforeSequence: 85,
          complete: true,
        ),
        isFalse,
      );
      expect(
        (await store.readMessages('account', 'group')).map((m) => m.sequence),
        [84, 85],
      );
      expect(await store.lastEventSequence('account', 'device'), 0);
      expect(await store.lastAckedEventSequence('account', 'device'), 0);
      expect(await store.pendingHistoryCatchups('other-account'), isEmpty);
    },
  );

  test(
    'clearing a conversation invalidates an in-flight history page',
    () async {
      final store = _store(inMemoryDatabasePath);
      addTearDown(store.close);
      await store.mergeMessages('account', 'group', [_message(84)]);
      await store.replaceBootstrap('account', _bootstrap(85));
      final old = (await store.pendingHistoryCatchups('account')).single;
      await store.clearConversationMessages('account', 'group');
      expect(
        await store.commitHistoryCatchupPage(
          'account',
          old,
          [_message(85)],
          nextBeforeSequence: 85,
          complete: true,
        ),
        isFalse,
      );
      expect(await store.readMessages('account', 'group'), isEmpty);
      expect(await store.pendingHistoryCatchups('account'), isEmpty);
    },
  );

  for (final mode in [
    'empty',
    'wrong-conversation',
    'wrong-sequence',
    'server-503',
    'switch-account',
    'logout',
    'cached',
  ]) {
    test('history repair protects data for $mode', () async {
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      FlutterSecureStorage.setMockInitialValues({});
      final sessions = SecureSessionStore();
      MobileSession session(String id) => MobileSession(
        accessToken: 'token-$id',
        deviceId: 'device',
        userId: id,
        displayName: 'Test',
        username: id,
        policySignatureKey: '',
        imApiUrl: 'http://127.0.0.1:${server.port}',
        oaApiUrl: '',
      );
      await sessions.saveSession(session('account'));
      final store = _store(inMemoryDatabasePath);
      addTearDown(store.close);
      await store.mergeMessages('account', 'group', [_message(84)]);
      await store.replaceBootstrap('account', _bootstrap(85));
      if (mode == 'cached') {
        await store.mergeMessages('account', 'group', [_message(85)]);
      }
      var calls = 0;
      server.listen((request) async {
        calls++;
        request.response.headers.contentType = ContentType.json;
        final payload = _messageJson(85);
        if (mode == 'wrong-conversation') payload['conversationId'] = 'another';
        if (mode == 'wrong-sequence') payload['sequence'] = 86;
        if (mode == 'server-503') request.response.statusCode = 503;
        if (mode == 'switch-account') {
          await sessions.saveSession(session('other-account'));
        }
        if (mode == 'logout') await sessions.clearSession();
        request.response.write(jsonEncode(mode == 'empty' ? [] : [payload]));
        await request.response.close();
      });
      final repository = ImRepository(
        CollaborationClient(sessions),
        sessions,
        store,
      );
      final result = await repository.repairAnnouncedMessageGaps();
      expect(result.changed, isEmpty);
      expect(result.progressed, mode == 'cached');
      expect(
        (await store.readMessages('account', 'group')).length,
        mode == 'cached' ? 2 : 1,
      );
      expect(await store.readMessages('other-account', 'group'), isEmpty);
      expect(
        await store.pendingHistoryCatchups('account'),
        mode == 'cached' ? isEmpty : hasLength(1),
      );
      if (mode != 'logout' && mode != 'switch-account') {
        expect(
          (await repository.repairAnnouncedMessageGaps()).changed,
          isEmpty,
        );
        expect(calls, mode == 'cached' ? 0 : 1);
      }
    });
  }
}

ImLocalStore _store(String path) =>
    ImLocalStore(factory: databaseFactoryFfi, pathResolver: () async => path);
ImMessage _message(int sequence) => ImMessage(
  id: 'message-$sequence',
  conversationId: 'group',
  sequence: sequence,
  senderId: 'other',
  clientMessageId: 'client-$sequence',
  content: 'message $sequence',
  kind: 'text',
  createdAt: DateTime.utc(2026, 9, 2, 10),
);
Map<String, Object?> _messageJson(int sequence) => {
  'id': 'message-$sequence',
  'conversationId': 'group',
  'sequence': sequence,
  'senderId': 'other',
  'clientMessageId': 'client-$sequence',
  'content': 'message $sequence',
  'kind': 'text',
  'createdAt': '2026-09-02T10:00:00Z',
};
ImBootstrap _bootstrap(int latest) => ImBootstrap(
  currentMember: const ImMember(
    id: 'member',
    username: 'test',
    displayName: 'Test',
    isOnline: true,
  ),
  contacts: const [],
  conversations: [
    ImConversation(
      id: 'group',
      type: 'group',
      title: 'Group',
      preview: 'latest',
      updatedAt: DateTime.utc(2026, 9, 2, 10),
      unreadCount: latest - 80,
      lastMessageSequence: latest,
      lastReadSequence: 80,
    ),
  ],
);

class _RealHttpOverrides extends HttpOverrides {}

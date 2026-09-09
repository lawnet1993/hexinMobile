import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'own desktop send is discovered even when unread total stays zero',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(switch (request.uri.path) {
            '/api/im/badges' => {
              'unreadMessages': 0,
              'pendingFriendRequests': 0,
            },
            '/api/im/conversations' => [_conversationJson(2)],
            '/api/im/conversations/group/messages' => [_messageJson(2)],
            _ => {},
          }),
        );
        await request.response.close();
      });
      FlutterSecureStorage.setMockInitialValues({});
      final sessions = SecureSessionStore();
      await sessions.saveSession(_session(server.port));
      final store = _store();
      addTearDown(store.close);
      await store.mergeMessages('account', 'group', [
        ImMessage.fromJson(_messageJson(1)),
      ]);
      await store.replaceBootstrap('account', _bootstrap(1));
      final repository = ImRepository(
        CollaborationClient(sessions),
        sessions,
        store,
      );
      expect(await repository.reconcileConversationIndex(), isTrue);
      expect(
        (await store.readBootstrap('account'))!
            .conversations
            .single
            .lastMessageSequence,
        2,
      );
      expect((await repository.repairAnnouncedMessageGaps()).changed, {
        'group',
      });
      expect(
        (await store.readMessages('account', 'group')).map((m) => m.sequence),
        [1, 2],
      );
      expect(
        (await store.readBootstrap('account'))!
            .conversations
            .single
            .unreadCount,
        0,
      );
      expect(paths, isNot(contains('/api/im/bootstrap')));
      expect(await repository.reconcileConversationIndex(force: true), isFalse);
      expect((await repository.repairAnnouncedMessageGaps()).changed, isEmpty);
      expect(paths.where((p) => p.endsWith('/messages')), hasLength(1));
    },
  );

  test(
    'partial index preserves other conversations and monotonic send/read state',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('account', _bootstrap(3));
      await store.mergeConversationIndex('account', [
        ImConversation.fromJson(_conversationJson(1, id: 'other')),
      ]);
      expect(
        (await store.readBootstrap('account'))!.conversations,
        hasLength(2),
      );
      expect(
        await store.mergeConversationIndex('account', [
          ImConversation.fromJson(_conversationJson(2)),
        ]),
        isFalse,
      );
      expect(
        (await store.readBootstrap('account'))!.conversations
            .singleWhere((c) => c.id == 'group')
            .lastMessageSequence,
        3,
      );
      await store.markConversationRead('account', 'group', 3);
      expect(
        await store.mergeConversationIndex('account', [
          ImConversation.fromJson(_conversationJson(4, read: 2)),
        ]),
        isFalse,
      );
      expect(
        (await store.readBootstrap('account'))!.conversations
            .singleWhere((c) => c.id == 'group')
            .lastReadSequence,
        3,
      );
      expect(
        await store.mergeConversationIndex('account', [
          ImConversation.fromJson(_conversationJson(4, read: 3)),
        ]),
        isTrue,
      );
      expect(await store.mergeConversationIndex('account', const []), isFalse);
      expect(
        (await store.readBootstrap('account'))!.conversations,
        hasLength(2),
      );
      expect(await store.readBootstrap('another-account'), isNull);
    },
  );

  test(
    'empty server preview falls back to the confirmed local message kind',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap(
        'account',
        ImBootstrap(
          currentMember: const ImMember(
            id: 'member',
            username: 'test',
            displayName: 'Test',
            isOnline: true,
          ),
          contacts: const [],
          conversations: [
            ImConversation.fromJson({
              ..._conversationJson(7),
              'lastMessagePreview': '',
            }),
          ],
        ),
      );
      await store.mergeMessages('account', 'group', [
        ImMessage.fromJson({
          ..._messageJson(7),
          'content': '',
          'kind': 'audio',
          'attachments': [
            {
              'id': 'audio-7',
              'type': 'audio',
              'fileName': 'AI-UAT-audio.wav',
              'contentType': 'audio/wav',
              'size': 14400078,
            },
          ],
        }),
      ]);

      final conversation = (await store.readBootstrap('account'))!
          .conversations
          .single;
      expect(conversation.preview, '[语音]');
    },
  );

  test(
    'index requests coalesce and respect throttle without repeated bootstrap',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final arrived = Completer<void>();
      final release = Completer<void>();
      var requests = 0;
      server.listen((request) async {
        requests++;
        if (!arrived.isCompleted) arrived.complete();
        await release.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode([_conversationJson(2)]));
        await request.response.close();
      });
      FlutterSecureStorage.setMockInitialValues({});
      final sessions = SecureSessionStore();
      await sessions.saveSession(_session(server.port));
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('account', _bootstrap(1));
      var now = DateTime.utc(2026, 9, 2, 12);
      final repository = ImRepository(
        CollaborationClient(sessions),
        sessions,
        store,
        conversationIndexClock: () => now,
      );
      final first = repository.reconcileConversationIndex();
      await arrived.future.timeout(const Duration(seconds: 5));
      final second = repository.reconcileConversationIndex();
      release.complete();
      expect(await Future.wait([first, second]), [true, true]);
      expect(requests, 1);
      expect(await repository.reconcileConversationIndex(), isFalse);
      expect(requests, 1);
      now = now.add(const Duration(seconds: 26));
      expect(await repository.reconcileConversationIndex(), isFalse);
      expect(requests, 2);
      expect(await repository.reconcileConversationIndex(force: true), isFalse);
      expect(requests, 3);
    },
  );

  for (final mode in [
    'switch-account',
    'logout',
    'empty',
    'malformed',
    'duplicate',
    'server-503',
  ]) {
    test(
      'index preserves cache on $mode and scopes responses to the login',
      () async {
        HttpOverrides.global = _RealHttpOverrides();
        addTearDown(() => HttpOverrides.global = null);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        FlutterSecureStorage.setMockInitialValues({});
        final sessions = SecureSessionStore();
        await sessions.saveSession(_session(server.port));
        final store = _store();
        addTearDown(store.close);
        await store.replaceBootstrap('account', _bootstrap(1));
        server.listen((request) async {
          if (mode == 'switch-account') {
            await sessions.saveSession(_session(server.port, id: 'another'));
          }
          if (mode == 'logout') await sessions.clearSession();
          if (mode == 'server-503') request.response.statusCode = 503;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(switch (mode) {
              'empty' => [],
              'malformed' => [
                {'id': '', 'type': 'group'},
              ],
              'duplicate' => [_conversationJson(2), _conversationJson(2)],
              _ => [_conversationJson(2)],
            }),
          );
          await request.response.close();
        });
        final repository = ImRepository(
          CollaborationClient(sessions),
          sessions,
          store,
        );
        if (['malformed', 'duplicate', 'server-503'].contains(mode)) {
          await expectLater(
            repository.reconcileConversationIndex(),
            throwsA(anything),
          );
        } else {
          expect(await repository.reconcileConversationIndex(), isFalse);
        }
        expect(
          (await store.readBootstrap('account'))!
              .conversations
              .single
              .lastMessageSequence,
          1,
        );
        expect(await store.readBootstrap('another'), isNull);
      },
    );
  }
}

ImLocalStore _store() => ImLocalStore(
  factory: databaseFactoryFfi,
  pathResolver: () async => inMemoryDatabasePath,
);
MobileSession _session(int port, {String id = 'account'}) => MobileSession(
  accessToken: 'local-token-$id',
  deviceId: 'device',
  userId: id,
  displayName: 'Test',
  username: id,
  policySignatureKey: '',
  imApiUrl: 'http://127.0.0.1:$port',
  oaApiUrl: '',
);
Map<String, Object?> _conversationJson(
  int sequence, {
  String id = 'group',
  int read = 1,
}) => {
  'id': id,
  'type': 'group',
  'title': 'Group',
  'lastMessagePreview': 'message $sequence',
  'lastMessageSequence': sequence,
  'lastReadSequence': read,
  'unreadCount': 0,
};
Map<String, Object?> _messageJson(int sequence) => {
  'id': 'message-$sequence',
  'conversationId': 'group',
  'sequence': sequence,
  'senderId': 'member',
  'clientMessageId': 'client-$sequence',
  'content': 'message $sequence',
  'kind': 'text',
};
ImBootstrap _bootstrap(int sequence) => ImBootstrap(
  currentMember: const ImMember(
    id: 'member',
    username: 'test',
    displayName: 'Test',
    isOnline: true,
  ),
  contacts: const [],
  conversations: [ImConversation.fromJson(_conversationJson(sequence))],
);

class _RealHttpOverrides extends HttpOverrides {}

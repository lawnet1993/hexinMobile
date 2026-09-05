import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const readPath = '/api/im/conversations/group/read';
const mentionsPath = '/api/im/mentions/unread';
const mentionReadPath = '/api/im/mentions/read';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final phase in [readPath, mentionsPath, mentionReadPath]) {
    for (final sameAccount in [false, true]) {
      for (final status in [200, 500]) {
        test(
          '$phase late $status after ${sameAccount ? 'relogin' : 'account switch'} cancels old read chain',
          () async {
            final f = await _Fixture.open();
            addTearDown(f.close);
            f.switchAt = phase;
            f.sameAccount = sameAccount;
            f.failureAt = status == 500 ? phase : null;
            Object? failure;
            try {
              await f.repository.markRead('group', 7);
            } catch (error) {
              failure = error;
            }
            expect(f.switched, isTrue);
            expect(f.requestAccounts.toSet(), {'a'});
            expect(f.requestTokens.toSet(), {'Bearer fixture-old'});
            expect(failure, isA<SessionChangedException>());
            final lastAllowed = [
              readPath,
              mentionsPath,
              mentionReadPath,
            ].indexOf(phase);
            expect(
              f.paths,
              [readPath, mentionsPath, mentionReadPath].take(lastAllowed + 1),
            );
            final a = (await f.store.readBootstrap('a'))!.conversations.single;
            final b = (await f.store.readBootstrap('b'))!.conversations.single;
            expect(a.lastReadSequence, phase == readPath ? 0 : 7);
            expect(b.lastReadSequence, 0);
            expect(b.unreadCount, 9);
            expect(
              (await f.sessions.readSession())!.accessToken,
              'fixture-new',
            );
          },
        );
      }
    }
  }
  test(
    'stable session marks only visible mentions and persists local read',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.repository.markRead('group', 7);
      expect(f.paths, [readPath, mentionsPath, mentionReadPath]);
      expect(f.markedIds, ['mention-3']);
      expect(f.readSequences, [7]);
      expect(f.requestTokens.toSet(), {'Bearer fixture-old'});
      final group = (await f.store.readBootstrap('a'))!.conversations.single;
      expect(group.lastReadSequence, 7);
      expect(group.unreadCount, 2);
      expect(group.unreadMentionSequences, [9]);
      expect(
        (await f.store.readBootstrap('b'))!
            .conversations
            .single
            .lastReadSequence,
        0,
      );
    },
  );
  test(
    'same-session primary read failure does not persist or fetch mentions',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      f.failureAt = readPath;
      await expectLater(
        f.repository.markRead('group', 7),
        throwsA(isA<DioException>()),
      );
      expect(f.paths, [readPath]);
      expect(
        (await f.store.readBootstrap('a'))!
            .conversations
            .single
            .lastReadSequence,
        0,
      );
    },
  );
  for (final phase in [mentionsPath, mentionReadPath]) {
    test(
      'same-session optional $phase failure keeps authoritative read',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        f.failureAt = phase;
        await f.repository.markRead('group', 7);
        expect(
          (await f.store.readBootstrap('a'))!
              .conversations
              .single
              .lastReadSequence,
          7,
        );
        expect((await f.sessions.readSession())!.accessToken, 'fixture-old');
      },
    );
  }
}

class _Fixture {
  _Fixture(this.server, this.sessions, this.store);
  final HttpServer server;
  final SecureSessionStore sessions;
  final ImLocalStore store;
  late final repository = ImRepository(
    CollaborationClient(sessions),
    sessions,
    store,
  );
  String? switchAt, failureAt;
  bool switched = false, sameAccount = false;
  final paths = <String>[],
      requestAccounts = <String>[],
      requestTokens = <String>[],
      markedIds = <String>[];
  final readSequences = <int>[];
  MobileSession session(String token, String account) => MobileSession(
    accessToken: token,
    deviceId: 'fixture-device',
    userId: account,
    displayName: 'Fixture',
    username: 'fixture',
    policySignatureKey: '',
    imApiUrl: 'http://127.0.0.1:${server.port}',
    oaApiUrl: '',
  );
  static Future<_Fixture> open() async {
    HttpOverrides.global = _RealHttpOverrides();
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sessions = SecureSessionStore();
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    final f = _Fixture(server, sessions, store);
    await sessions.saveSession(f.session('fixture-old', 'a'));
    for (final account in ['a', 'b']) {
      await store.replaceBootstrap(
        account,
        ImBootstrap.fromJson({
          'currentMember': {'id': account, 'displayName': 'Fixture'},
          'contacts': [],
          'conversations': [
            {
              'id': 'group',
              'type': 'group',
              'title': 'Fixture',
              'lastMessageSequence': 9,
              'lastReadSequence': 0,
              'unreadCount': 9,
              'unreadMentionSequences': [3, 9],
            },
          ],
        }),
      );
      await store.mergeMessages(account, 'group', [
        for (var i = 1; i <= 9; i++)
          ImMessage.fromJson({
            'id': 'message-$i',
            'clientMessageId': 'client-$i',
            'conversationId': 'group',
            'sequence': i,
            'senderId': 'peer',
            'kind': 'text',
            'content': 'Fixture',
          }),
      ]);
    }
    server.listen((request) async {
      final path = request.uri.path;
      f.paths.add(path);
      f.requestAccounts.add(
        request.headers.value('X-Terminal-Account-Id') ?? '',
      );
      f.requestTokens.add(request.headers.value('Authorization') ?? '');
      if (request.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if (path == readPath) f.readSequences.add(body['sequence'] as int);
        if (path == mentionReadPath) {
          f.markedIds.addAll((body['messageIds'] as List).cast<String>());
        }
      }
      if (!f.switched && f.switchAt == path) {
        f.switched = true;
        await sessions.saveSession(
          f.session('fixture-new', f.sameAccount ? 'a' : 'b'),
        );
      }
      request.response.headers.contentType = ContentType.json;
      if (f.failureAt == path) request.response.statusCode = 500;
      request.response.write(
        jsonEncode(
          path == mentionsPath
              ? [
                  {
                    'messageId': 'mention-3',
                    'conversationId': 'group',
                    'sequence': 3,
                  },
                  {
                    'messageId': 'mention-9',
                    'conversationId': 'group',
                    'sequence': 9,
                  },
                ]
              : {'affected': 1},
        ),
      );
      await request.response.close();
    });
    return f;
  }

  Future<void> close() async {
    await server.close(force: true);
    await store.close();
    HttpOverrides.global = null;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

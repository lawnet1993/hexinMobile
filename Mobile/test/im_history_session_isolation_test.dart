import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final operation in ['refresh', 'reconcile', 'older', 'cache-miss', 'anchor']) {
    for (final change in ['account', 'relogin', 'logout']) {
      for (final status in [200, 401, 409, 500]) {
        test(
          '$operation discards late $status after $change without persisting or replacing session',
          () async {
            final f = await _Fixture.open();
            addTearDown(f.close);
            f.changeOnRequest = change;
            f.status = status;
            await expectLater(
              f.run(operation),
              throwsA(isA<SessionChangedException>()),
            );
            expect(f.requestAccounts, ['a']);
            expect(f.requestCredentials, ['Bearer fixture-old']);
            expect(await f.store.readMessages('a', 'group'), isEmpty);
            expect(await f.store.readMessages('b', 'group'), isEmpty);
            final current = await f.sessions.readSession();
            if (change == 'logout') {
              expect(current, isNull);
            } else {
              expect(current?.accessToken, 'fixture-new');
              expect(current?.userId, change == 'account' ? 'b' : 'a');
            }
          },
        );
      }
    }
  }
  for (final operation in [
    'cached',
    'older-cached',
    'older-cursor',
    'reconcile',
    'anchor-cached',
  ]) {
    for (final change in ['account', 'relogin', 'logout']) {
      test(
        '$operation rejects cache result when $change occurs during decoding',
        () async {
          final f = await _Fixture.open();
          addTearDown(f.close);
          await f.store.mergeMessages('a', 'group', [_message(1)]);
          f.cipher.beforeReveal = () => f.change(change);
          await expectLater(
            f.run(operation),
            throwsA(isA<SessionChangedException>()),
          );
          expect(f.requestAccounts, operation == 'reconcile' ? ['a'] : isEmpty);
          expect(
            (await f.store.readMessages('a', 'group')).single.content,
            'Synthetic old history',
          );
          expect(await f.store.readMessages('b', 'group'), isEmpty);
        },
      );
    }
  }
  for (final operation in ['cache-miss', 'older-cursor', 'anchor']) {
    test(
      '$operation cancels before requesting or returning an empty old-account cache',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        f.beforeOpen = () => f.change('account');
        await expectLater(
          f.run(operation),
          throwsA(isA<SessionChangedException>()),
        );
        expect(
          f.requestAccounts,
          isEmpty,
          reason: 'must not start a new-account request for an old operation',
        );
        expect(await f.store.readMessages('a', 'group'), isEmpty);
        expect(await f.store.readMessages('b', 'group'), isEmpty);
      },
    );
  }
  for (final operation in ['refresh', 'reconcile', 'older', 'cache-miss', 'anchor']) {
    test(
      '$operation current-session success persists only its own messages and leaves reads untouched',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        for (final account in ['a', 'b']) {
          await f.store.replaceBootstrap(
            account,
            ImBootstrap.fromJson({
              'currentMember': {'id': account},
              'contacts': [],
              'conversations': [
                {
                  'id': 'group',
                  'type': 'group',
                  'title': 'Synthetic group',
                  'lastMessageSequence': 9,
                  'lastReadSequence': 0,
                  'unreadCount': 9,
                },
              ],
            }),
          );
        }
        await f.run(operation);
        expect(
          (await f.store.readMessages('a', 'group')).single.content,
          'Synthetic old history',
        );
        expect(await f.store.readMessages('b', 'group'), isEmpty);
        for (final account in ['a', 'b']) {
          final conversation = (await f.store.readBootstrap(account))!
              .conversations
              .single;
          expect(conversation.lastReadSequence, 0);
          expect(conversation.unreadCount, 9);
        }
        expect(f.requestAccounts, ['a']);
        expect(f.queries.single['take'], operation == 'older' || operation == 'anchor' ? '80' : '50');
        expect(
          f.queries.single['beforeSequence'],
          operation == 'older' || operation == 'anchor' ? '10' : null,
        );
      },
    );
    for (final status in [401, 409, 500]) {
      test(
        '$operation current-session $status remains an error without local logout or cache write',
        () async {
          final f = await _Fixture.open();
          addTearDown(f.close);
          f.status = status;
          await expectLater(f.run(operation), throwsA(isA<DioException>()));
          expect((await f.sessions.readSession())?.accessToken, 'fixture-old');
          expect(await f.store.readMessages('a', 'group'), isEmpty);
        },
      );
    }
  }
  test(
    'unchanged reconciliation reuses cached objects and makes no read request',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.store.mergeMessages('a', 'group', [_message(1)]);
      final prior = (await f.store.readMessages('a', 'group')).single;
      expect(await f.repository.reconcileLatestMessages('group'), isFalse);
      expect((await f.store.readMessages('a', 'group')).single, same(prior));
      expect(f.paths, ['/api/im/conversations/group/messages']);
    },
  );
  test('anchor reads only its cached sequence range excluding newer and pending messages', () async {
    final f=await _Fixture.open();addTearDown(f.close);
    await f.store.mergeMessages('a','group',[for(var i=0;i<=200;i++)_message(i)]);
    final slice=await f.repository.messagesBeforeCacheFirst('group',take:80,beforeSequence:121);
    expect(slice.map((item)=>item.sequence),List.generate(80,(i)=>i+41));
    expect(f.paths,isEmpty);
    final earliest=await f.repository.messagesBeforeCacheFirst('group',take:80,beforeSequence:41);
    expect(earliest.map((item)=>item.sequence),List.generate(40,(i)=>i+1));
    expect(f.paths,isEmpty);
  });
  test('anchor does not mistake sparse old cache rows for complete unread coverage', () async {
    final f=await _Fixture.open();addTearDown(f.close);
    await f.store.mergeMessages('a','group',[_message(1)]);
    await f.repository.messagesBeforeCacheFirst('group',take:80,beforeSequence:81);
    expect(f.queries.single,{'take':'80','beforeSequence':'81'});
  });
  test('anchor rejects invalid bounds before opening cache or network', () async {
    final f=await _Fixture.open();addTearDown(f.close);
    await expectLater(f.repository.messagesBeforeCacheFirst('group',take:0,beforeSequence:2),throwsArgumentError);
    await expectLater(f.repository.messagesBeforeCacheFirst('group',take:80,beforeSequence:0),throwsArgumentError);
    expect(await f.repository.messagesBeforeCacheFirst('group',take:80,beforeSequence:1),isEmpty);
    expect(f.paths,isEmpty);
  });
  for (final invalid in [
    {'conversationId': 'other-group', 'sequence': 1},
    {'conversationId': 'group', 'sequence': 0},
    {'conversationId': 'group', 'sequence': 10},
  ]) {
    test('anchor rejects a response outside its conversation or range: $invalid', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      f.responseItems = [{'id': 'invalid', 'senderId': 'peer', 'kind': 'text', ...invalid}];
      await expectLater(f.run('anchor'), throwsStateError);
      expect(await f.store.readMessages('a', 'group'), isEmpty);
      expect(await f.store.readMessages('a', 'other-group'), isEmpty);
    });
  }
}

ImMessage _message(int sequence) => ImMessage(
  id: 'message-$sequence',
  conversationId: 'group',
  sequence: sequence,
  senderId: 'peer',
  content: 'Synthetic old history',
  kind: 'text',
  createdAt: null,
);

class _Fixture {
  _Fixture(this.server, this.sessions);
  final HttpServer server;
  final SecureSessionStore sessions;
  final cipher = _SwitchingCipher();
  Future<void> Function()? beforeOpen;
  late final store = ImLocalStore(
    factory: databaseFactoryFfi,
    cipher: cipher,
    pathResolver: () async {
      final hook = beforeOpen;
      beforeOpen = null;
      await hook?.call();
      return inMemoryDatabasePath;
    },
  );
  late final repository = ImRepository(
    CollaborationClient(sessions),
    sessions,
    store,
  );
  String? changeOnRequest;
  int status = 200;
  List<Map<String, Object?>>? responseItems;
  final requestAccounts = <String>[],
      requestCredentials = <String>[],
      paths = <String>[];
  final queries = <Map<String, String>>[];
  MobileSession session(String account, String credential) => MobileSession(
    accessToken: credential,
    deviceId: 'fixture-device',
    userId: account,
    displayName: 'Fixture',
    username: 'fixture',
    policySignatureKey: '',
    imApiUrl: 'http://127.0.0.1:${server.port}',
    oaApiUrl: '',
  );
  Future<void> change(String kind) async {
    if (kind == 'logout') {
      await sessions.clearSession();
      return;
    }
    await sessions.saveSession(
      session(kind == 'account' ? 'b' : 'a', 'fixture-new'),
    );
  }

  Future<Object?> run(String operation) => switch (operation) {
    'refresh' => repository.refreshMessages('group'),
    'reconcile' => repository.reconcileLatestMessages('group'),
    'older' => repository.loadOlderMessages('group', beforeSequence: 10),
    'older-cached' => repository.loadOlderMessages('group', beforeSequence: 2),
    'older-cursor' => repository.loadOlderMessages('group'),
    'anchor' => repository.messagesBeforeCacheFirst('group',take:80,beforeSequence:10),
    'anchor-cached' => repository.messagesBeforeCacheFirst('group',take:80,beforeSequence:2),
    _ => repository.messagesCacheFirst('group', take: 80),
  };
  static Future<_Fixture> open() async {
    HttpOverrides.global = _RealHttpOverrides();
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final f = _Fixture(server, SecureSessionStore());
    await f.sessions.saveSession(f.session('a', 'fixture-old'));
    server.listen((request) async {
      f.paths.add(request.uri.path);
      f.queries.add(request.uri.queryParameters);
      f.requestAccounts.add(
        request.headers.value('X-Terminal-Account-Id') ?? '',
      );
      f.requestCredentials.add(request.headers.value('Authorization') ?? '');
      final change = f.changeOnRequest;
      f.changeOnRequest = null;
      if (change != null) await f.change(change);
      request.response.statusCode = f.status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          f.status == 200
              ? f.responseItems ?? [
                  {
                    'id': 'message-1',
                    'conversationId': 'group',
                    'sequence': 1,
                    'senderId': 'peer',
                    'content': 'Synthetic old history',
                    'kind': 'text',
                  },
                ]
              : {
                  'code': f.status == 409
                      ? 'session_replaced'
                      : 'synthetic_error',
                },
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

class _SwitchingCipher implements ImCacheCipher {
  Future<void> Function()? beforeReveal;
  @override
  bool get isEnabled => false;
  @override
  bool isProtected(String value) => false;
  @override
  Future<String> protect(String accountId, String value) async => value;
  @override
  Future<String> reveal(String accountId, String value) async {
    final hook = beforeReveal;
    beforeReveal = null;
    await hook?.call();
    return value;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

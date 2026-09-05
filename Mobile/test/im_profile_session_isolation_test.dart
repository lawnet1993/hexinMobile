import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final operation in ['load', 'save', 'avatar']) {
    for (final change in ['account', 'relogin', 'logout']) {
      for (final status in [200, 500]) {
        test(
          '$operation late $status after $change cannot publish or refresh another login',
          () async {
            final f = await _Fixture.create();
            f.change = change;
            f.status = status;
            Object? failure;
            try {
              await f.perform(operation);
            } catch (error) {
              failure = error;
            }
            expect(f.accounts.toSet(), {'a'});
            expect(failure, isA<SessionChangedException>());
            expect(f.paths, hasLength(1));
            expect(f.accounts, ['a']);
            expect(await f.store.readBootstrap('b'), isNull);
            expect(await f.store.readBootstrap('a'), isNull);
          },
        );
      }
    }
    test('$operation stable session remains usable', () async {
      final f = await _Fixture.create();
      await f.perform(operation);
      expect(f.accounts.toSet(), {'a'});
      expect(f.paths.length, operation == 'load' ? 1 : 2);
      if (operation != 'load') {
        expect((await f.store.readBootstrap('a'))!.currentMember.id, 'a');
      }
    });
    test('$operation stable 500 preserves its network failure', () async {
      final f = await _Fixture.create();
      f.status = 500;
      await expectLater(f.perform(operation), throwsA(isA<DioException>()));
      expect(f.paths, hasLength(1));
    });
  }
  for (final operation in ['save', 'avatar']) {
    for (final change in ['account', 'relogin', 'logout']) {
      test(
        'dialog-bound $operation rejects a later $change before HTTP',
        () async {
          final f = await _Fixture.create();
          final original = (await f.sessions.readSession())!;
          await f.transition(change);
          await expectLater(
            operation == 'save'
                ? f.repository.updateProfile(
                    nickname: 'old draft',
                    signature: '',
                    expectedSession: original,
                  )
                : f.repository.updateAvatar(
                    avatarKey: 'work',
                    expectedSession: original,
                  ),
            throwsA(isA<SessionChangedException>()),
          );
          expect(f.paths, isEmpty);
        },
      );
      for (final status in [200, 500]) {
        test(
          '$operation bootstrap late $status after $change remains isolated',
          () async {
            final f = await _Fixture.create();
            f.change = change;
            f.changeAt = 2;
            f.statusAt = 2;
            f.status = status;
            await expectLater(
              f.perform(operation),
              throwsA(isA<SessionChangedException>()),
            );
            expect(f.accounts, ['a', 'a']);
            expect(await f.store.readBootstrap('a'), isNull);
            expect(await f.store.readBootstrap('b'), isNull);
          },
        );
      }
    }
  }
}

class _Fixture {
  _Fixture(this.server, this.sessions, this.store)
    : repository = ImRepository(CollaborationClient(sessions), sessions, store);
  final HttpServer server;
  final SecureSessionStore sessions;
  final ImLocalStore store;
  final ImRepository repository;
  String? change;
  int status = 200;
  int changeAt = 1;
  int statusAt = 1;
  final paths = <String>[];
  final accounts = <String>[];

  MobileSession session(String token, String user) => MobileSession(
    accessToken: token,
    deviceId: 'fixture-device',
    userId: user,
    username: user,
    displayName: user,
    policySignatureKey: '',
    imApiUrl: 'http://127.0.0.1:${server.port}',
    oaApiUrl: '',
  );

  Future<void> transition(String change) async {
    if (change == 'logout') {
      await sessions.clearSession();
    } else {
      await sessions.saveSession(
        session('fixture-new', change == 'account' ? 'b' : 'a'),
      );
    }
  }

  Future<void> perform(String operation) async {
    switch (operation) {
      case 'load':
        await repository.memberProfile('a');
      case 'save':
        await repository.updateProfile(
          nickname: 'Edited',
          signature: 'Fixture',
        );
      case 'avatar':
        await repository.updateAvatar(avatarKey: 'work');
    }
  }

  static Future<_Fixture> create() async {
    HttpOverrides.global = _RealHttp();
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sessions = SecureSessionStore();
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    final f = _Fixture(server, sessions, store);
    await sessions.saveSession(f.session('fixture-old', 'a'));
    server.listen((request) async {
      f.paths.add(request.uri.path);
      final account = request.headers.value('X-Terminal-Account-Id') ?? '';
      f.accounts.add(account);
      await request.drain<void>();
      if (f.paths.length == f.changeAt && f.change != null) {
        await f.transition(f.change!);
      }
      request.response.statusCode = f.paths.length == f.statusAt
          ? f.status
          : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          request.uri.path == '/api/im/bootstrap'
              ? {
                  'currentMember': {'id': account, 'username': account},
                  'conversations': [],
                  'contacts': [],
                }
              : {'id': 'a', 'displayName': 'Edited', 'nickname': 'Edited'},
        ),
      );
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await store.close();
      HttpOverrides.global = null;
      FlutterSecureStorage.setMockInitialValues({});
    });
    return f;
  }
}

class _RealHttp extends HttpOverrides {}

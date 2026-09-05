import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late HttpServer server;
  late SecureSessionStore sessions;
  late ImRepository repository;
  late Completer<void> entered;
  late Completer<void> response;
  late List<({String method, String? account, String? token})> calls;
  MobileSession session(String account) => MobileSession(
    accessToken: 'fixture-$account',
    deviceId: 'fixture-device',
    userId: account,
    username: account,
    displayName: account,
    policySignatureKey: '',
    imApiUrl: 'http://127.0.0.1:${server.port}',
    oaApiUrl: '',
  );
  setUp(() async {
    HttpOverrides.global = _RealHttp();
    FlutterSecureStorage.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sessions = SecureSessionStore();
    await sessions.saveSession(session('a'));
    repository = ImRepository(
      CollaborationClient(sessions),
      sessions,
      ImLocalStore(factory: databaseFactoryFfi),
    );
    entered = Completer<void>();
    response = Completer<void>();
    calls = [];
    server.listen((request) async {
      calls.add((
        method: request.method,
        account: request.headers.value('X-Terminal-Account-Id'),
        token: request.headers.value('Authorization'),
      ));
      await request.drain<void>();
      entered.complete();
      await response.future;
      request.response.statusCode = 204;
      await request.response.close();
    });
  });
  tearDown(() async {
    if (!response.isCompleted) response.complete();
    await server.close(force: true);
    HttpOverrides.global = null;
  });
  for (final operation in ['register', 'unregister']) {
    test('$operation rejects stale supplied session before sending', () async {
      final old = session('a');
      await sessions.saveSession(session('b'));
      final future = operation == 'register'
          ? repository.registerPushDevice(
              platform: 'android',
              provider: 'fcm',
              token: 'fixture-token',
              forSession: old,
            )
          : repository.unregisterPushDevice(forSession: old);
      await expectLater(future, throwsA(isA<SessionChangedException>()));
      expect(calls, isEmpty);
    });
    test('$operation in flight stays bound to its original account', () async {
      final old = session('a');
      final future = operation == 'register'
          ? repository.registerPushDevice(
              platform: 'android',
              provider: 'fcm',
              token: 'fixture-token',
              forSession: old,
            )
          : repository.unregisterPushDevice(forSession: old);
      final checked = operation == 'register'
          ? expectLater(future, throwsA(isA<SessionChangedException>()))
          : expectLater(future, completes);
      await entered.future;
      await sessions.saveSession(session('b'));
      response.complete();
      await checked;
      expect(calls, [
        (
          method: operation == 'register' ? 'PUT' : 'DELETE',
          account: 'a',
          token: 'Bearer fixture-a',
        ),
      ]);
      expect((await sessions.readSession())?.userId, 'b');
    });
  }
}

class _RealHttp extends HttpOverrides {}

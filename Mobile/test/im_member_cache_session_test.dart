import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final paged in [false, true]) {
    for (final mode in ['accepted', 'relogin', 'other-account', 'logout']) {
      test(
        'member cache ${paged ? 'page' : 'full'} isolates $mode response',
        () async {
          HttpOverrides.global = _RealHttp();
          addTearDown(() => HttpOverrides.global = null);
          FlutterSecureStorage.setMockInitialValues({});
          final sessions = SecureSessionStore();
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));
          MobileSession session(String account, String token) => MobileSession(
            userId: account,
            username: account,
            displayName: account,
            deviceId: 'fixture-device',
            accessToken: token,
            policySignatureKey: '',
            imApiUrl: 'http://127.0.0.1:${server.port}',
            oaApiUrl: '',
          );
          final original = session('a', 'fixture-old');
          await sessions.saveSession(original);
          final local = ImLocalStore(
            factory: databaseFactoryFfi,
            pathResolver: () async => inMemoryDatabasePath,
          );
          addTearDown(local.close);
          final entered = Completer<void>();
          final release = Completer<void>();
          var calls = 0;
          server.listen((request) async {
            calls++;
            entered.complete();
            await release.future;
            const members = [
              {
                'id': 'peer',
                'username': 'peer',
                'displayName': 'Peer',
                'isOnline': false,
                'lastSeenAt': '2026-09-03T00:00:00Z',
              },
            ];
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode(
                paged
                    ? {'items': members, 'page': 1, 'pageSize': 50, 'total': 1}
                    : members,
              ),
            );
            await request.response.close();
          });
          final repository = ImRepository(
            CollaborationClient(sessions),
            sessions,
            local,
          );
          final Future<Object?> pending = paged
              ? repository.conversationMemberPage('group')
              : repository.refreshConversationMembers('group');
          final assertion = mode == 'accepted'
              ? null
              : expectLater(pending, throwsA(isA<SessionChangedException>()));
          await entered.future;
          if (mode == 'relogin') {
            await sessions.saveSession(session('a', 'fixture-new'));
          }
          if (mode == 'other-account') {
            await sessions.saveSession(session('b', 'fixture-new'));
          }
          if (mode == 'logout') await sessions.clearSessionIfCurrent(original);
          release.complete();
          if (assertion == null) {
            await pending;
          } else {
            await assertion;
          }
          final cached = await local.readConversationMembers('a', 'group');
          if (mode == 'accepted') {
            expect(
              cached.single.lastSeenAt,
              DateTime.utc(2026, 9, 3).toLocal(),
            );
          } else {
            expect(cached, isEmpty);
          }
          expect(await local.readConversationMembers('b', 'group'), isEmpty);
          expect(calls, 1);
        },
      );
    }
  }
}

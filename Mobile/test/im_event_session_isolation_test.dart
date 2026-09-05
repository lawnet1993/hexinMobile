import 'dart:convert';
import 'dart:io';

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
  for (final phase in ['events', 'bootstrap']) {
    for (final sameAccount in [false, true]) {
      test(
        'discard late $phase after ${sameAccount ? 'same account relogin' : 'account switch'}',
        () async {
          HttpOverrides.global = _RealHttpOverrides();
          addTearDown(() => HttpOverrides.global = null);
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));
          FlutterSecureStorage.setMockInitialValues({});
          final sessions = SecureSessionStore();
          MobileSession session(String token, String account) => MobileSession(
            accessToken: token,
            userId: account,
            deviceId: 'fixture-device',
            displayName: 'Fixture',
            username: 'fixture',
            policySignatureKey: '',
            imApiUrl: 'http://127.0.0.1:${server.port}',
            oaApiUrl: '',
          );
          await sessions.saveSession(session('fixture-old', 'a'));
          var bootstrapCalls = 0;
          var ackCalls = 0;
          server.listen((request) async {
            request.response.headers.contentType = ContentType.json;
            final endpoint = request.uri.path.split('/').last;
            if (endpoint == phase) {
              await sessions.saveSession(
                session('fixture-new', sameAccount ? 'a' : 'b'),
              );
            }
            Object payload = {};
            if (endpoint == 'events') {
              payload = {
                'latestSequence': 1,
                'events': [
                  {
                    'id': 'event-1',
                    'sequence': 1,
                    'type': 'message.created',
                    'payloadJson': jsonEncode({
                      'id': 'message-1',
                      'sequence': 1,
                      'conversationId': 'direct',
                      'senderId': 'peer',
                      'clientMessageId': 'client-1',
                      'content': 'old session body',
                      'kind': 'text',
                    }),
                  },
                ],
              };
            } else if (endpoint == 'bootstrap') {
              bootstrapCalls++;
              payload = {
                'currentMember': {
                  'id': 'a',
                  'username': 'fixture',
                  'displayName': 'Fixture',
                },
                'contacts': [],
                'conversations': [],
              };
            } else if (endpoint == 'ack') {
              ackCalls++;
            }
            request.response.write(jsonEncode(payload));
            await request.response.close();
          });
          final store = ImLocalStore(
            factory: databaseFactoryFfi,
            pathResolver: () async => inMemoryDatabasePath,
          );
          addTearDown(store.close);
          var committedCallbacks = 0;
          final result =
              await ImRepository(
                CollaborationClient(sessions),
                sessions,
                store,
              ).pullEvents(
                waitSeconds: 0,
                onCommitted: (_) => committedCallbacks++,
              );
          expect(result.changed, isFalse);
          expect(committedCallbacks, 0);
          expect(bootstrapCalls, phase == 'events' ? 0 : 1);
          expect(ackCalls, 0);
          expect(await store.lastEventSequence('a', 'fixture-device'), 0);
          expect(await store.readBootstrap('a'), isNull);
          expect(await store.readMessages('a', 'direct'), isEmpty);
          expect(await store.readMessages('b', 'direct'), isEmpty);
        },
      );
    }
  }
}

class _RealHttpOverrides extends HttpOverrides {}

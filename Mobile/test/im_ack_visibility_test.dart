import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/im_sync_coordinator.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final status in [200, 500, 401, 409]) {
    test(
      'committed message is published before held ACK $status completes',
      () async {
        HttpOverrides.global = _RealHttpOverrides();
        FlutterSecureStorage.setMockInitialValues({});
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sessions = SecureSessionStore();
        await sessions.saveSession(
          MobileSession(
            accessToken: 'local-ack-visibility-fixture',
            deviceId: 'fixture-device',
            userId: 'account',
            displayName: 'Fixture',
            username: 'fixture',
            policySignatureKey: '',
            imApiUrl: 'http://127.0.0.1:${server.port}',
            oaApiUrl: '',
          ),
        );
        final store = ImLocalStore(
          factory: databaseFactoryFfi,
          pathResolver: () async => inMemoryDatabasePath,
        );
        final container = ProviderContainer();
        final ackEntered = Completer<void>();
        final releaseAck = Completer<void>();
        final releasePoll = Completer<void>();
        final nextPoll = Completer<void>();
        final authFailure = Completer<int>();
        final changes = <ImSyncInvalidation>[];
        var bootstrapCalls = 0;
        var ackCalls = 0;
        var enteredWithMessages = 0;
        final coordinator = ImSyncCoordinator(
          ImRepository(CollaborationClient(sessions), sessions, store),
          availabilityController: container.read(
            imRealtimeAvailabilityControllerProvider.notifier,
          ),
          onChanged: changes.add,
          onSessionInvalid: (error) async {
            if (!authFailure.isCompleted) {
              authFailure.complete(error.response!.statusCode!);
            }
            return true;
          },
        );
        addTearDown(() async {
          final stopped = coordinator.stop();
          if (!releaseAck.isCompleted) releaseAck.complete();
          if (!releasePoll.isCompleted) releasePoll.complete();
          await stopped;
          await server.close(force: true);
          await store.close();
          container.dispose();
          HttpOverrides.global = null;
        });
        Map<String, Object?> conversation() => {
          'id': 'direct',
          'type': 'direct',
          'title': 'Fixture',
          'lastMessageSequence': bootstrapCalls > 1 ? 1 : 0,
          'lastReadSequence': 0,
          'unreadCount': 0,
        };
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          Object payload = {};
          switch (request.uri.path) {
            case '/api/im/bootstrap':
              bootstrapCalls++;
              payload = {
                'currentMember': {'id': 'account'},
                'contacts': [],
                'conversations': [conversation()],
              };
            case '/api/im/conversations':
              payload = [conversation()];
            case '/api/im/conversations/direct/messages':
              payload = [];
            case '/api/im/sync/events':
              if (request.uri.queryParameters['afterSequence'] == '0') {
                payload = {
                  'events': [
                    {
                      'id': 'event-1',
                      'sequence': 1,
                      'type': 'message.created',
                      'payloadJson': jsonEncode({
                        'id': 'message-1',
                        'sequence': 1,
                        'conversationId': 'direct',
                        'senderId': 'account',
                        'clientMessageId': 'client-1',
                        'content': 'same-account other-device fixture',
                        'kind': 'text',
                      }),
                    },
                  ],
                };
              } else {
                if (!nextPoll.isCompleted) nextPoll.complete();
                await releasePoll.future;
                payload = {'events': []};
              }
            case '/api/im/sync/ack':
              ackCalls++;
              enteredWithMessages = (await store.readMessages(
                'account',
                'direct',
              )).length;
              if (!ackEntered.isCompleted) ackEntered.complete();
              await releaseAck.future;
              request.response.statusCode = status;
              if (status == 409) payload = {'code': 'session_replaced'};
          }
          try {
            request.response.write(jsonEncode(payload));
            await request.response.close();
          } catch (_) {
            // stop cancels the held request.
          }
        });
        await coordinator.start();
        await ackEntered.future.timeout(const Duration(seconds: 5));
        expect(enteredWithMessages, 1);
        expect(await store.lastEventSequence('account', 'fixture-device'), 1);
        expect(
          await store.lastAckedEventSequence('account', 'fixture-device'),
          0,
        );
        expect(
          changes.where(
            (change) => change.messageConversationIds.contains('direct'),
          ),
          hasLength(1),
          reason: 'SQLite commit must publish independently of a stalled ACK',
        );
        releaseAck.complete();
        if (status == 200) {
          await nextPoll.future.timeout(const Duration(seconds: 5));
          expect(
            await store.lastAckedEventSequence('account', 'fixture-device'),
            1,
          );
        } else if (status == 401 || status == 409) {
          expect(
            await authFailure.future.timeout(const Duration(seconds: 5)),
            status,
          );
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(authFailure.isCompleted, isFalse);
        }
        expect(
          changes.where(
            (change) => change.messageConversationIds.contains('direct'),
          ),
          hasLength(1),
          reason: 'ACK completion must not publish the same change twice',
        );
        expect(ackCalls, 1);
        expect(
          (await store.readMessages('account', 'direct')).single.id,
          'message-1',
        );
        if (status != 200) {
          expect(
            await store.lastAckedEventSequence('account', 'fixture-device'),
            0,
          );
        }
      },
    );
  }
}

class _RealHttpOverrides extends HttpOverrides {}

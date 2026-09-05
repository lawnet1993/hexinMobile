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
  for (final total in [500, 510, 1000]) {
    test(
      '$total events drain full pages without long-poll and ACK only persisted messages',
      () async {
        HttpOverrides.global = _RealHttpOverrides();
        addTearDown(() => HttpOverrides.global = null);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        FlutterSecureStorage.setMockInitialValues({});
        final sessions = SecureSessionStore();
        await sessions.saveSession(
          MobileSession(
            accessToken: 'local-fixture',
            deviceId: 'device',
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
        addTearDown(store.close);
        final pulls = <({int after, int wait, int take})>[];
        final acks =
            <({int sequence, int applied, int previousAck, int stored})>[];
        final drained = Completer<void>();
        final returnedToLongPoll = Completer<void>();
        final release = Completer<void>();
        var drainRequests = 0;
        var prematureRepairs = 0;
        Map<String, Object?> conversation() => {
          'id': 'group',
          'type': 'group',
          'title': 'Fixture',
          'lastMessageSequence': total,
          'lastReadSequence': 0,
          'unreadCount': total - total ~/ 10,
        };
        server.listen((request) async {
          Object payload = {};
          request.response.headers.contentType = ContentType.json;
          switch (request.uri.path) {
            case '/api/im/bootstrap':
              payload = {
                'currentMember': {'id': 'account', 'displayName': 'Fixture'},
                'contacts': [],
                'conversations': [conversation()],
              };
            case '/api/im/conversations':
              if (acks.isNotEmpty && acks.last.sequence < total) {
                prematureRepairs++;
              }
              payload = [conversation()];
            case '/api/im/conversations/group/messages':
              if (acks.isEmpty || acks.last.sequence < total) {
                prematureRepairs++;
              }
              payload = [];
            case '/api/im/sync/events':
              final query = request.uri.queryParameters;
              final after = int.parse(query['afterSequence']!);
              pulls.add((
                after: after,
                wait: int.parse(query['waitSeconds']!),
                take: int.parse(query['take']!),
              ));
              if (after >= total) {
                if (++drainRequests == 1) {
                  drained.complete();
                } else if (query['waitSeconds'] == '25') {
                  if (!returnedToLongPoll.isCompleted) {
                    returnedToLongPoll.complete();
                  }
                  await release.future;
                }
              }
              payload = {
                'events': [
                  for (var i = after + 1; i <= total && i <= after + 500; i++)
                    {
                      'id': 'event-$i',
                      'sequence': i,
                      'type': 'message.created',
                      'payloadJson': jsonEncode({
                        'id': 'message-$i',
                        'clientMessageId': 'client-$i',
                        'sequence': i,
                        'conversationId': 'group',
                        'senderId': i % 10 == 0 ? 'account' : 'peer',
                        'kind': 'text',
                        'content': 'batch fixture $i',
                      }),
                    },
                ],
                'latestSequence': total,
              };
            case '/api/im/sync/ack':
              final body =
                  jsonDecode(await utf8.decoder.bind(request).join()) as Map;
              acks.add((
                sequence: body['eventSequence'] as int,
                applied: await store.lastEventSequence('account', 'device'),
                previousAck: await store.lastAckedEventSequence(
                  'account',
                  'device',
                ),
                stored: (await store.readMessages('account', 'group')).length,
              ));
          }
          try {
            request.response.write(jsonEncode(payload));
            await request.response.close();
          } catch (_) {
            /* The coordinator may cancel its final held request. */
          }
        });
        final container = ProviderContainer.test();
        addTearDown(container.dispose);
        final coordinator = ImSyncCoordinator(
          ImRepository(CollaborationClient(sessions), sessions, store),
          availabilityController: container.read(
            imRealtimeAvailabilityControllerProvider.notifier,
          ),
          onChanged: (_) {},
        );
        try {
          await coordinator.start();
          await drained.future.timeout(const Duration(seconds: 20));
          await returnedToLongPoll.future.timeout(const Duration(seconds: 5));
        } finally {
          await coordinator.stop();
          release.complete();
        }
        final expectedAcks = total == 500 ? [500] : [500, total];
        expect(acks.map((sample) => sample.sequence), expectedAcks);
        for (var i = 0; i < acks.length; i++) {
          expect(acks[i].applied, acks[i].sequence);
          expect(acks[i].stored, acks[i].sequence);
          expect(acks[i].previousAck, i == 0 ? 0 : acks[i - 1].sequence);
        }
        expect(await store.lastAckedEventSequence('account', 'device'), total);
        expect(pulls.every((pull) => pull.take == 500), isTrue);
        expect(
          pulls.take(total == 1000 ? 3 : 2).map((pull) => pull.after),
          total == 1000 ? [0, 500, 1000] : [0, 500],
        );
        final messages = await store.readMessages('account', 'group');
        expect(
          messages.map((message) => message.sequence),
          List.generate(total, (i) => i + 1),
        );
        expect(messages.map((message) => message.id).toSet(), hasLength(total));
        expect(
          messages.map((message) => message.clientMessageId).toSet(),
          hasLength(total),
        );
        expect(
          messages.where((message) => message.senderId == 'account'),
          hasLength(total ~/ 10),
        );
        final group = (await store.readBootstrap('account'))!
            .conversations
            .single;
        expect(group.lastReadSequence, 0);
        expect(group.unreadCount, total - total ~/ 10);
        expect(prematureRepairs, 0);
        // Completing an already-announced history job may add one final
        // immediate probe; it must then return to a held long-poll.
        expect(pulls.length, lessThanOrEqualTo((total / 500).ceil() + 3));
        expect(
          pulls.last.wait,
          25,
          reason: 'No busy poll once the backlog is empty',
        );
        expect(
          pulls.take(total == 1000 ? 3 : 2).map((pull) => pull.wait),
          total == 1000 ? [25, 0, 0] : [25, 0],
        );
      },
    );
  }
}

class _RealHttpOverrides extends HttpOverrides {}

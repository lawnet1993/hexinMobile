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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final (conversationType, mode) in [
    for (final type in ['direct', 'group'])
      for (final mode in ['crash-before-ack', 'ack-500', 'switch-before-ack'])
        (type, mode),
  ]) {
    test(
      '$conversationType $mode keeps committed messages and replays ACK without duplicates',
      () async {
        HttpOverrides.global = _RealHttpOverrides();
        addTearDown(() => HttpOverrides.global = null);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final directory = await Directory.systemTemp.createTemp(
          'im-ack-recovery-',
        );
        addTearDown(() => directory.delete(recursive: true));
        FlutterSecureStorage.setMockInitialValues({});
        final sessions = SecureSessionStore();
        MobileSession session(String account) => MobileSession(
          accessToken: 'fixture-$account',
          userId: account,
          deviceId: 'device',
          displayName: 'Fixture',
          username: 'fixture',
          policySignatureKey: '',
          imApiUrl: 'http://127.0.0.1:${server.port}',
          oaApiUrl: '',
        );
        await sessions.saveSession(session('account'));
        final requests = <String>[];
        final acks = <int>[];
        var failAck = mode == 'ack-500';
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          final endpoint = request.uri.path.split('/').last;
          requests.add(endpoint);
          Object payload = {};
          if (endpoint == 'events') {
            // Intentionally replay the same event, even when afterSequence=1.
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
                    'conversationId': conversationType,
                    'senderId': 'peer',
                    'clientMessageId': 'client-1',
                    'content': 'encrypted fixture',
                    'kind': 'text',
                    if (conversationType == 'group')
                      'mentions': [
                        {
                          'mentionedMemberId': 'account',
                          'displayName': 'Fixture',
                        },
                      ],
                  }),
                },
              ],
            };
          } else if (endpoint == 'bootstrap') {
            payload = {
              'currentMember': {
                'id': 'account',
                'username': 'fixture',
                'displayName': 'Fixture',
              },
              'contacts': [],
              'conversations': [
                {
                  'id': conversationType,
                  'type': conversationType,
                  'title': 'Fixture',
                  'lastMessageSequence': 1,
                  'lastReadSequence': 0,
                  'unreadCount': 1,
                  if (conversationType == 'group')
                    'unreadMentionSequences': [1],
                },
              ],
            };
          } else if (endpoint == 'ack') {
            final body =
                jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            acks.add(body['eventSequence'] as int);
            if (failAck) {
              failAck = false;
              request.response.statusCode = 500;
            }
          }
          request.response.write(jsonEncode(payload));
          await request.response.close();
        });
        final path = '${directory.path}/im.db';
        ImLocalStore open() => ImLocalStore(
          factory: databaseFactoryFfi,
          pathResolver: () async => path,
          cipher: AesGcmImCacheCipher((_) async => List<int>.filled(32, 9)),
        );
        var store = open();
        addTearDown(() => store.close());
        final repository = ImRepository(
          CollaborationClient(sessions),
          sessions,
          store,
          beforeEventAck: (sequence, events) async {
            expect(sequence, 1);
            expect(await store.lastEventSequence('account', 'device'), 1);
            expect(await store.lastAckedEventSequence('account', 'device'), 0);
            expect(
              (await store.readMessages('account', conversationType)).single.id,
              'message-1',
            );
            if (mode == 'crash-before-ack') {
              throw const _SimulatedCrash();
            }
            if (mode == 'switch-before-ack') {
              await sessions.saveSession(session('other'));
            }
          },
        );
        if (mode == 'switch-before-ack') {
          expect(
            (await repository.pullEvents(waitSeconds: 0)).changed,
            isFalse,
          );
          expect(await store.readMessages('other', conversationType), isEmpty);
          await sessions.saveSession(session('account'));
        } else {
          await expectLater(
            repository.pullEvents(waitSeconds: 0),
            throwsA(
              mode == 'ack-500' ? isA<DioException>() : isA<_SimulatedCrash>(),
            ),
          );
        }
        expect(await store.lastEventSequence('account', 'device'), 1);
        expect(await store.lastAckedEventSequence('account', 'device'), 0);
        expect(acks.length, mode == 'ack-500' ? 1 : 0);
        await store.close();
        store = open();
        requests.clear();
        var replayCallbacks = 0;
        await ImRepository(
          CollaborationClient(sessions),
          sessions,
          store,
        ).pullEvents(waitSeconds: 0, onCommitted: (_) => replayCallbacks++);
        expect(
          replayCallbacks,
          0,
          reason: 'Already applied replay must not republish',
        );
        expect(requests, ['ack', 'events', 'ack']);
        expect(acks, List.filled(mode == 'ack-500' ? 3 : 2, 1));
        expect(await store.lastAckedEventSequence('account', 'device'), 1);
        expect(await store.lastEventSequence('account', 'another-device'), 0);
        final messages = await store.readMessages('account', conversationType);
        expect(messages, hasLength(1));
        expect(messages.single.content, 'encrypted fixture');
        expect(
          messages.single.mentions.map((value) => value.mentionedMemberId),
          conversationType == 'group' ? ['account'] : isEmpty,
        );
        final conversation = (await store.readBootstrap('account'))!
            .conversations
            .single;
        expect(conversation.type, conversationType);
        expect(conversation.lastReadSequence, 0);
        expect(conversation.firstUnreadSequence, 1);
        expect(
          conversation.unreadMentionSequences,
          conversationType == 'group' ? [1] : isEmpty,
        );
        expect(
          (await store.readBootstrap('account'))!
              .conversations
              .single
              .unreadCount,
          1,
        );
        await store.close();
        final raw = await databaseFactoryFfi.openDatabase(path);
        try {
          expect(await raw.query('im_event_inbox'), hasLength(1));
          expect(
            (await raw.query('im_messages')).single['content'],
            startsWith('enc:v1:'),
          );
        } finally {
          await raw.close();
        }
      },
    );
  }
}

class _RealHttpOverrides extends HttpOverrides {}

final class _SimulatedCrash implements Exception {
  const _SimulatedCrash();
}

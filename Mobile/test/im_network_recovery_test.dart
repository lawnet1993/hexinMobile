import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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

  test('network recovery interrupts long poll and persists announced messages before waiting again', () async {
    HttpOverrides.global = _RealHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final network = StreamController<List<ConnectivityResult>>.broadcast(
      sync: true,
    );
    addTearDown(network.close);
    final firstPull = Completer<void>();
    final secondLongPull = Completer<void>();
    final releaseLongPolls = Completer<void>();
    addTearDown(() {
      if (!releaseLongPolls.isCompleted) releaseLongPolls.complete();
    });
    final repaired = Completer<void>();
    final waits = <String?>[];
    var indexRequests = 0;
    var historyRequests = 0;
    var sendRequests = 0;
    var announced = 0;
    Map<String, Object?> conversation() => {
      'id': 'group',
      'type': 'group',
      'title': 'Test group',
      'lastMessageSequence': announced,
      'lastReadSequence': 0,
      'unreadCount': announced,
      'unreadMentionSequences': announced == 0 ? [] : [1],
    };
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      Object payload;
      switch (request.uri.path) {
        case '/api/im/conversations/outgoing/messages':
          sendRequests++;
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          payload = {
            'id': 'sent-1',
            'clientMessageId': body['clientMessageId'],
            'conversationId': 'outgoing',
            'sequence': 1,
            'senderId': 'account',
            'kind': 'text',
            'content': body['content'],
          };
        case '/api/im/bootstrap':
          payload = {
            'currentMember': {
              'id': 'account',
              'username': 'test',
              'displayName': 'Test',
            },
            'contacts': [],
            'conversations': [conversation()],
          };
        case '/api/im/sync/events':
          final wait = request.uri.queryParameters['waitSeconds'];
          waits.add(wait);
          if (wait != '0') {
            if (!firstPull.isCompleted) {
              firstPull.complete();
            } else if (!secondLongPull.isCompleted) {
              secondLongPull.complete();
            }
            await releaseLongPolls.future;
          }
          payload = {'events': [], 'latestSequence': 0};
        case '/api/im/conversations':
          indexRequests++;
          payload = [conversation()];
        case '/api/im/conversations/group/messages':
          historyRequests++;
          payload = [
            {
              'id': 'message-1',
              'clientMessageId': 'client-1',
              'conversationId': 'group',
              'sequence': 1,
              'senderId': 'other',
              'kind': 'text',
              'content': 'network recovery fixture',
            },
          ];
        default:
          payload = {};
      }
      try {
        request.response.write(jsonEncode(payload));
        await request.response.close();
      } catch (_) {
        // The cancelled held request is expected to have a closed socket.
      }
    });
    FlutterSecureStorage.setMockInitialValues({});
    final sessions = SecureSessionStore();
    await sessions.saveSession(
      MobileSession(
        accessToken: 'local-fixture-token',
        deviceId: 'local-device',
        userId: 'account',
        displayName: 'Test',
        username: 'test',
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
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final coordinator = ImSyncCoordinator(
      ImRepository(CollaborationClient(sessions), sessions, store),
      connectivityChanges: network.stream,
      availabilityController: container.read(
        imRealtimeAvailabilityControllerProvider.notifier,
      ),
      onChanged: (change) {
        if (change.messageConversationIds.contains('group') &&
            !repaired.isCompleted) {
          repaired.complete();
        }
      },
    );
    addTearDown(coordinator.stop);
    await coordinator.start();
    await firstPull.future.timeout(const Duration(seconds: 5));
    await store.enqueueText(
      accountId: 'account',
      senderId: 'account',
      conversationId: 'outgoing',
      clientMessageId: 'stable-client',
      content: 'offline fixture',
    );
    await store.markOutboxFailed(
      'account',
      (await store.dueOutbox('account')).single,
      'offline',
      retryScheduled: true,
      retryOnConnectionChange: true,
    );
    expect(await store.dueOutbox('account'), isEmpty);
    network.add([ConnectivityResult.none]);
    announced = 1;
    network.add([ConnectivityResult.wifi]);
    await repaired.future.timeout(const Duration(seconds: 3));
    expect(waits.take(2), ['25', '0']);
    expect((await store.readMessages('account', 'group')).single.sequence, 1);
    final summary = (await store.readBootstrap('account'))!
        .conversations
        .single;
    expect(summary.unreadCount, 1);
    expect(summary.lastReadSequence, 0);
    expect(summary.unreadMentionSequences, [1]);
    expect(sendRequests, 1);
    expect(
      (await store.readMessages('account', 'outgoing')).single.id,
      'sent-1',
    );
    expect(await store.dueOutbox('account'), isEmpty);
    await secondLongPull.future.timeout(const Duration(seconds: 3));
    final beforeDuplicates = indexRequests;
    for (var i = 0; i < 4; i++) {
      network.add([ConnectivityResult.wifi]);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(indexRequests, beforeDuplicates);
    expect(historyRequests, 1);
    expect(sendRequests, 1);
    await coordinator.stop();
    expect(network.hasListener, isFalse);
    network.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(indexRequests, beforeDuplicates);
  });
}

class _RealHttpOverrides extends HttpOverrides {}

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
  late Directory directory;
  late HttpServer server;
  late ImLocalStore store;
  late ImRepository repository;
  late SecureSessionStore sessions;
  late List<String> requests;

  setUp(() async {
    HttpOverrides.global = _RealHttpOverrides();
    directory = await Directory.systemTemp.createTemp('im-cached-history-');
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add('${request.method} ${request.uri}');
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
    });
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SecureSessionStore();
    await sessions.saveSession(
      MobileSession(
        accessToken: 'test-only',
        deviceId: 'test-device',
        userId: 'account-a',
        displayName: 'Test',
        username: 'test',
        policySignatureKey: '',
        imApiUrl: 'http://${server.address.address}:${server.port}',
        oaApiUrl: '',
      ),
    );
    store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => '${directory.path}/history.db',
      cipher: AesGcmImCacheCipher((_) async => List<int>.filled(32, 42)),
    );
    repository = ImRepository(CollaborationClient(sessions), sessions, store);
  });
  tearDown(() async {
    await store.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
    HttpOverrides.global = null;
  });

  for (final conversation in ['direct', 'group']) {
    test(
      '$conversation history pages survive cold reopen without HTTP',
      () async {
        await store.mergeMessages(
          'account-a',
          conversation,
          List.generate(173, (i) => _message(conversation, i + 1)),
        );
        await store.close();
        store = ImLocalStore(
          factory: databaseFactoryFfi,
          pathResolver: () async => '${directory.path}/history.db',
          cipher: AesGcmImCacheCipher((_) async => List<int>.filled(32, 42)),
        );
        repository = ImRepository(
          CollaborationClient(sessions),
          sessions,
          store,
        );
        final recent = await repository.messagesCacheFirst(
          conversation,
          take: 80,
        );
        expect(
          recent.map((m) => m.sequence),
          orderedEquals(List.generate(80, (i) => i + 94)),
        );
        final older = await repository.loadOlderMessages(
          conversation,
          beforeSequence: 94,
        );
        expect(
          older.map((m) => m.sequence),
          orderedEquals(List.generate(80, (i) => i + 14)),
        );
        final first = await repository.loadOlderMessages(
          conversation,
          beforeSequence: 14,
        );
        expect(
          first.map((m) => m.sequence),
          orderedEquals(List.generate(13, (i) => i + 1)),
        );
        expect(
          await repository.loadOlderMessages(conversation, beforeSequence: 1),
          isEmpty,
        );
        expect(requests, isEmpty);
      },
    );
  }

  test(
    'a short adjacent cache page does not skip a missing sequence',
    () async {
      await store.mergeMessages('account-a', 'group', [
        for (final seq in [1, 2, 3, 8, 9, 10]) _message('group', seq),
      ]);
      final adjacent = await repository.loadOlderMessages(
        'group',
        beforeSequence: 10,
      );
      expect(adjacent.map((m) => m.sequence), [8, 9]);
      expect(requests, isEmpty);
      await expectLater(
        repository.loadOlderMessages('group', beforeSequence: 8),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            405,
          ),
        ),
      );
      expect(requests.single, contains('beforeSequence=8'));
      expect(
        requests.single,
        startsWith('GET /api/im/conversations/group/messages'),
      );
    },
  );

  test('cached history remains account and conversation scoped', () async {
    await store.mergeMessages('account-b', 'group', [_message('group', 9)]);
    await store.mergeMessages('account-a', 'direct', [_message('direct', 9)]);
    await expectLater(
      repository.loadOlderMessages('group', beforeSequence: 10),
      throwsA(isA<DioException>()),
    );
    expect(requests, hasLength(1));
  });

  test(
    'deleted messages establish continuity but are not resurrected',
    () async {
      await store.mergeMessages('account-a', 'group', [
        for (final seq in [7, 8, 9]) _message('group', seq),
      ]);
      await store.applySyncBatch(
        accountId: 'account-a',
        deviceId: 'test-device',
        bootstrap: const ImBootstrap(
          currentMember: ImMember(
            id: 'sender',
            username: 'test',
            displayName: 'Test',
            isOnline: true,
          ),
          contacts: [],
          conversations: [],
        ),
        events: [
          ImSyncEvent(
            id: 'delete-8',
            sequence: 1,
            type: 'message.deleted',
            payloadJson: '{"id":"group-8","messageId":"group-8"}',
            createdAt: DateTime.utc(2026, 9, 2),
          ),
        ],
      );
      final older = await repository.loadOlderMessages(
        'group',
        beforeSequence: 10,
      );
      expect(older.map((m) => m.sequence), [7, 9]);
      expect(requests, isEmpty);
    },
  );
}

ImMessage _message(String conversation, int sequence) => ImMessage(
  id: '$conversation-$sequence',
  conversationId: conversation,
  sequence: sequence,
  senderId: 'sender',
  content: 'AI-UAT-CACHE-$sequence',
  kind: 'text',
  createdAt: DateTime.utc(2026, 9, 2, 8, 0, sequence),
);

class _RealHttpOverrides extends HttpOverrides {}

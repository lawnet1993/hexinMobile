import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_outbox_file_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RealHttp extends HttpOverrides {}

class _ReadBoundaryCipher implements ImCacheCipher {
  Future<void> Function()? onReveal;
  @override
  bool get isEnabled => false;
  @override
  bool isProtected(String value) => false;
  @override
  Future<String> protect(String accountId, String value) async => value;
  @override
  Future<String> reveal(String accountId, String value) async {
    final boundary = onReveal;
    onReveal = null;
    await boundary?.call();
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late HttpServer server;
  late SecureSessionStore sessions;
  late ImLocalStore store;
  late ImRepository repository;
  late Directory directory;
  late _ReadBoundaryCipher cipher;
  late List<({String path, String? account, String? auth})> calls;
  late Map<String, String> queued;
  late Map<String, String> confirmed;
  Future<int> Function(String path)? respond;
  Map<String, Object?>? errorBody;
  MobileSession session(String account, String token) => MobileSession(
    accessToken: token,
    deviceId: 'fixture-device',
    userId: account,
    username: account,
    displayName: account,
    policySignatureKey: '',
    imApiUrl: 'http://127.0.0.1:${server.port}',
    oaApiUrl: '',
  );
  Future<void> transition(String kind) async {
    if (kind == 'logout') {
      await sessions.clearSession();
    } else {
      await sessions.saveSession(
        session(kind == 'account' ? 'b' : 'a', 'fixture-new'),
      );
    }
  }

  Future<ImMessage> queue(String kind, [String conversation = 'chat']) async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final message = await switch (kind) {
      'text' => repository.send(conversation, 'fixture'),
      'contact' => repository.sendContactCard(conversation, 'peer'),
      'file' => repository.sendAttachment(
        conversationId: conversation,
        fileName: 'fixture.txt',
        bytes: bytes,
      ),
      'image' => repository.sendImages(
        conversationId: conversation,
        files: [
          (fileName: 'fixture.png', bytes: bytes, contentType: 'image/png'),
        ],
      ),
      _ => repository.sendMedia(
        conversationId: conversation,
        kind: kind,
        fileName: 'fixture.$kind',
        bytes: bytes,
        contentType: kind == 'video' ? 'video/mp4' : 'audio/mpeg',
        coverBytes: kind == 'video' ? bytes : null,
      ),
    };
    queued[conversation] = message.clientMessageId;
    return message;
  }

  Future<void> expectPending(String conversation, String id) async {
    final item = await store.outboxItem('a', id);
    expect(item, isNotNull);
    expect(item!.attempts, 0);
    expect(
      (await store.readMessages('a', conversation)).single.localStatus,
      ImLocalMessageStatus.pending,
    );
    expect(await store.readMessages('b', conversation), isEmpty);
  }

  setUp(() async {
    HttpOverrides.global = _RealHttp();
    FlutterSecureStorage.setMockInitialValues({});
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    sessions = SecureSessionStore();
    await sessions.saveSession(session('a', 'fixture-old'));
    directory = await Directory.systemTemp.createTemp('im-outbox-session-');
    cipher = _ReadBoundaryCipher();
    store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => '${directory.path}/im.db',
      cipher: cipher,
    );
    repository = ImRepository(
      CollaborationClient(sessions),
      sessions,
      store,
      outboxFileStore: ImOutboxFileStore(
        keyLoader: sessions.readOrCreateImCacheKey,
        directoryLoader: () async => directory,
      ),
    );
    calls = [];
    queued = {};
    confirmed = {};
    respond = null;
    errorBody = null;
    server.listen((request) async {
      final path = request.uri.path;
      calls.add((
        path: path,
        account: request.headers.value('X-Terminal-Account-Id'),
        auth: request.headers.value('Authorization'),
      ));
      Map<String, Object?>? payload;
      if (request.headers.contentType?.mimeType == 'application/json') {
        payload = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
            .cast<String, Object?>();
      } else {
        await request.drain<void>();
      }
      final status = await respond?.call(path) ?? 200;
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      if (status != 200) {
        request.response.write(
          jsonEncode(
            errorBody ??
                {'code': status == 409 ? 'session_replaced' : 'fixture_error'},
          ),
        );
      } else if (path.startsWith('/api/im/upload/')) {
        request.response.write(
          jsonEncode({'objectId': 'fixture-object', 'size': 4}),
        );
      } else {
        final conversation = path.split('/')[4];
        final id =
            payload?['clientMessageId']?.toString() ??
            queued[conversation] ??
            'fixture-missing';
        final serverId = confirmed.putIfAbsent(id, () => 'server-$id');
        request.response.write(
          jsonEncode({
            'id': serverId,
            'clientMessageId': id,
            'conversationId': conversation,
            'senderId': 'a',
            'sequence': 1,
            'content': 'fixture',
            'kind': 'text',
          }),
        );
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await store.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
    HttpOverrides.global = null;
  });

  for (final kind in ['text', 'contact', 'file', 'image', 'audio', 'video']) {
    test(
      '$kind queue-read account switch sends no old payload under new identity',
      () async {
        final message = await queue(kind);
        cipher.onReveal = () => transition('account');
        final result = await repository.flushOutboxDetailed();
        expect(calls, isEmpty);
        expect(result.deliveredCount, 0);
        expect(result.conversationIds, isEmpty);
        await expectPending('chat', message.clientMessageId);
        expect((await sessions.readSession())!.userId, 'b');
      },
    );
  }
  for (final change in ['account', 'relogin', 'logout']) {
    for (final status in [200, 503, 401, 409]) {
      test(
        '$change late $status stops batch, preserves pending IDs and safe replay',
        () async {
          final first = await queue('text', 'first');
          final next = await queue('text', 'next');
          respond = (_) async {
            if (calls.length != 1) return 200;
            await transition(change);
            return status;
          };
          final result = await repository.flushOutboxDetailed();
          expect(calls, hasLength(1));
          expect(calls.single.account, 'a');
          expect(calls.single.auth, 'Bearer fixture-old');
          expect(result.deliveredCount, 0);
          expect(result.conversationIds, isEmpty);
          await expectPending('first', first.clientMessageId);
          await expectPending('next', next.clientMessageId);
          expect(
            (await sessions.readSession())?.accessToken,
            change == 'logout' ? null : 'fixture-new',
          );
          await sessions.saveSession(session('a', 'fixture-restored'));
          expect((await repository.flushOutboxDetailed()).deliveredCount, 2);
          expect(confirmed, hasLength(2));
          expect(await store.dueOutbox('a'), isEmpty);
          expect(
            (await store.readMessages('a', 'first')).single.clientMessageId,
            first.clientMessageId,
          );
          expect(
            calls
                .skip(1)
                .every(
                  (value) =>
                      value.account == 'a' &&
                      value.auth == 'Bearer fixture-restored',
                ),
            isTrue,
          );
        },
      );
    }
    for (final stage in ['video', 'picture']) {
      test('$change after $stage upload cannot continue media chain', () async {
        final message = await queue('video');
        respond = (path) async {
          if (path == '/api/im/upload/$stage') await transition(change);
          return 200;
        };
        final result = await repository.flushOutboxDetailed();
        expect(calls.map((value) => value.path), [
          '/api/im/upload/video',
          if (stage == 'picture') '/api/im/upload/picture',
        ]);
        expect(result.deliveredCount, 0);
        expect(result.conversationIds, isEmpty);
        await expectPending('chat', message.clientMessageId);
        expect(confirmed, isEmpty);
        await sessions.saveSession(session('a', 'fixture-restored'));
        final preview = await repository.readQueuedMediaPreview(
          message.attachments.single.id,
        );
        expect(preview, Uint8List.fromList([1, 2, 3, 4]));
      });
    }
  }
  for (final status in [401, 409]) {
    test(
      'current $status propagates to session coordinator without failing queue',
      () async {
        final message = await queue('text');
        respond = (_) async => status;
        await expectLater(
          repository.flushOutboxDetailed(),
          throwsA(isA<DioException>()),
        );
        expect(calls, hasLength(1));
        await expectPending('chat', message.clientMessageId);
      },
    );
    for (final stage in ['video', 'picture']) {
      test(
        '$stage $status cannot continue media upload after session failure',
        () async {
          final message = await queue('video');
          respond = (path) async =>
              path == '/api/im/upload/$stage' ? status : 200;
          await expectLater(
            repository.flushOutboxDetailed(),
            throwsA(isA<DioException>()),
          );
          expect(calls.map((call) => call.path), [
            '/api/im/upload/video',
            if (stage == 'picture') '/api/im/upload/picture',
          ]);
          await expectPending('chat', message.clientMessageId);
        },
      );
    }
  }

  test('session replacement accepts the coordinator Code spelling', () async {
    final message = await queue('text');
    errorBody = {'Code': ' SESSION_REPLACED '};
    respond = (_) async => 409;
    await expectLater(
      repository.flushOutboxDetailed(),
      throwsA(isA<DioException>()),
    );
    await expectPending('chat', message.clientMessageId);
  });

  for (final status in [403, 409]) {
    test(
      'business $status fails its message without expiring the session',
      () async {
        final message = await queue('text');
        errorBody = {'code': 'fixture_business_error'};
        respond = (_) async => status;
        final result = await repository.flushOutboxDetailed();
        expect(result.deliveredCount, 0);
        expect(result.conversationIds, {'chat'});
        expect(
          (await store.outboxItem('a', message.clientMessageId))!.attempts,
          1,
        );
        expect((await sessions.readSession())!.accessToken, 'fixture-old');
      },
    );
  }

  test(
    'optional cover 503 still sends video under its original session',
    () async {
      final message = await queue('video');
      respond = (path) async => path == '/api/im/upload/picture' ? 503 : 200;
      expect((await repository.flushOutboxDetailed()).deliveredCount, 1);
      expect(calls.map((call) => call.path), [
        '/api/im/upload/video',
        '/api/im/upload/picture',
        '/api/im/conversations/chat/media-messages',
      ]);
      expect(await store.outboxItem('a', message.clientMessageId), isNull);
    },
  );

  for (final kind in ['contact', 'file', 'image', 'audio', 'video']) {
    test(
      '$kind late success keeps pending payload for stable-ID replay',
      () async {
        final message = await queue(kind);
        respond = (path) async {
          if (path.contains('/conversations/')) await transition('account');
          return 200;
        };
        final result = await repository.flushOutboxDetailed();
        expect(result.deliveredCount, 0);
        expect(result.conversationIds, isEmpty);
        expect(calls.every((call) => call.account == 'a'), isTrue);
        await expectPending('chat', message.clientMessageId);
        await sessions.saveSession(session('a', 'fixture-restored'));
        respond = null;
        expect((await repository.flushOutboxDetailed()).deliveredCount, 1);
        expect(confirmed.keys, [message.clientMessageId]);
        expect(
          (await store.readMessages('a', 'chat')).single.clientMessageId,
          message.clientMessageId,
        );
      },
    );
  }
}

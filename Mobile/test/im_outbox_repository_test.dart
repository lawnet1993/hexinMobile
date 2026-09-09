import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_outbox_file_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('one conversation 503 does not stall another conversation', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <String>[];
    var unavailable = true;
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final id = body['clientMessageId'] as String;
      calls.add(body['content'] as String);
      request.response.headers.contentType = ContentType.json;
      final conversation = request.uri.path.split('/')[4];
      if (conversation == 'blocked' && unavailable) {
        request.response.statusCode = 503;
        request.response.write('{}');
      } else {
        request.response.write(
          jsonEncode({
            'id': 'server-$id',
            'clientMessageId': id,
            'conversationId': conversation,
            'senderId': 'member-1',
            'sequence': calls.length,
            'content': body['content'],
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
      await request.response.close();
    });
    FlutterSecureStorage.setMockInitialValues({});
    final sessions = SecureSessionStore();
    await sessions.saveSession(
      MobileSession(
        accessToken: 'local-test-token',
        deviceId: 'local-test-device',
        userId: 'member-1',
        displayName: '测试',
        username: 'local-test',
        policySignatureKey: '',
        imApiUrl: 'http://127.0.0.1:${server.port}',
        oaApiUrl: '',
      ),
    );
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    final repository = ImRepository(
      CollaborationClient(sessions),
      sessions,
      store,
    );
    try {
      final first = await repository.send('blocked', 'first');
      await repository.send('blocked', 'second');
      final other = await repository.send('independent', 'other');
      final result = await repository.flushOutboxDetailed();
      expect(result.deliveredCount, 1);
      expect(calls, ['first', 'other']);
      expect(
        (await store.readMessages(
          'member-1',
          'blocked',
        )).every((item) => item.localStatus == ImLocalMessageStatus.pending),
        isTrue,
      );
      expect(
        (await store.readMessages(
          'member-1',
          'independent',
        )).single.clientMessageId,
        other.clientMessageId,
      );
      expect(
        (await store.readMessages(
          'member-1',
          'independent',
        )).single.localStatus,
        ImLocalMessageStatus.sent,
      );
      expect((await repository.flushOutboxDetailed()).deliveredCount, 0);
      expect(calls, ['first', 'other']);
      unavailable = false;
      await repository.retryMessage('blocked', first.clientMessageId);
      expect((await repository.flushOutboxDetailed()).deliveredCount, 2);
      expect(calls, ['first', 'other', 'first', 'second']);
      expect((await store.readMessages('member-1', 'blocked')), hasLength(2));
      expect(await store.dueOutbox('member-1'), isEmpty);
    } finally {
      await store.close();
      await server.close(force: true);
      HttpOverrides.global = null;
    }
  });

  test(
    'outbox-backed sends return local pending messages before network',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        const MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '测试成员',
          username: 'term.member1',
          policySignatureKey: '',
          imApiUrl: 'http://127.0.0.1:1',
          oaApiUrl: '',
        ),
      );
      final store = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => inMemoryDatabasePath,
      );
      final queueDirectory = await Directory.systemTemp.createTemp(
        'im-outbox-repository-',
      );
      final outboxFiles = ImOutboxFileStore(
        keyLoader: sessionStore.readOrCreateImCacheKey,
        directoryLoader: () async => queueDirectory,
      );
      final repository = ImRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
        outboxFileStore: outboxFiles,
      );

      try {
        final text = await repository.send('conversation-1', 'offline text');
        final file = await repository.sendAttachment(
          conversationId: 'conversation-1',
          fileName: 'offline.txt',
          bytes: Uint8List.fromList([1, 2, 3]),
          contentType: 'text/plain',
        );
        final contact = await repository.sendContactCard(
          'conversation-1',
          'member-2',
        );
        final image = await repository.sendImages(
          conversationId: 'conversation-1',
          files: [
            (
              fileName: 'offline.jpg',
              bytes: Uint8List.fromList([4, 5, 6]),
              contentType: 'image/jpeg',
            ),
          ],
        );
        final audio = await repository.sendMedia(
          conversationId: 'conversation-1',
          kind: 'audio',
          fileName: 'offline.mp3',
          bytes: Uint8List.fromList([7, 8, 9]),
          contentType: 'audio/mpeg',
        );

        expect(text.localStatus, ImLocalMessageStatus.pending);
        expect(file.localStatus, ImLocalMessageStatus.pending);
        expect(contact.localStatus, ImLocalMessageStatus.pending);
        expect(image.localStatus, ImLocalMessageStatus.pending);
        expect(audio.localStatus, ImLocalMessageStatus.pending);
        expect(image.images, hasLength(1));
        expect(audio.attachments, hasLength(1));
        expect(
          (await repository.downloadAttachment(file)).bytes,
          Uint8List.fromList([1, 2, 3]),
        );
        final mediaProgress = <(int, int)>[];
        expect(
          await repository.downloadMediaAttachment(
            audio.attachments.single.id,
            onReceiveProgress: (received, total) =>
                mediaProgress.add((received, total)),
          ),
          Uint8List.fromList([7, 8, 9]),
        );
        expect(mediaProgress, [(3, 3)]);
        final due = await store.dueOutbox('member-1');
        expect(due, hasLength(5));
        final queuedFile = due.singleWhere((item) => item.kind == 'file');
        expect(queuedFile.attachmentBytes, isEmpty);
        expect(queuedFile.mediaFiles, hasLength(1));
        expect(queuedFile.mediaFiles.single.role, 'file');
        expect(
          await outboxFiles.readBytes(
            accountId: 'member-1',
            clientMessageId: queuedFile.clientMessageId,
            file: queuedFile.mediaFiles.single,
          ),
          Uint8List.fromList([1, 2, 3]),
        );
        final cached = await store.readMessages('member-1', 'conversation-1');
        expect(cached, hasLength(5));
        expect(
          cached.every(
            (message) => message.localStatus == ImLocalMessageStatus.pending,
          ),
          isTrue,
        );
      } finally {
        await store.close();
        await queueDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'file attachment streams through part file and removes partial on cancel',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        const MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '测试成员',
          username: 'term.member1',
          policySignatureKey: '',
          imApiUrl: 'http://127.0.0.1:1',
          oaApiUrl: '',
        ),
      );
      final directory = await Directory.systemTemp.createTemp(
        'im-attachment-stream-',
      );
      final store = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => inMemoryDatabasePath,
      );
      final outboxFiles = ImOutboxFileStore(
        keyLoader: sessionStore.readOrCreateImCacheKey,
        directoryLoader: () async => Directory(path.join(directory.path, 'q')),
      );
      final repository = ImRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
        outboxFileStore: outboxFiles,
      );
      final bytes = Uint8List.fromList(
        List<int>.generate(1024 * 1024 + 17, (index) => index % 251),
      );
      final message = await repository.sendAttachment(
        conversationId: 'conversation-1',
        fileName: 'large.bin',
        bytes: bytes,
        contentType: 'application/octet-stream',
      );
      final target = File(path.join(directory.path, 'opened.bin'));

      try {
        final progress = <(int, int)>[];
        final downloaded = await repository.downloadAttachmentToFile(
          message,
          target.path,
          onReceiveProgress: (received, total) =>
              progress.add((received, total)),
        );
        expect(downloaded.path, target.path);
        expect(await target.readAsBytes(), bytes);
        expect(await File('${target.path}.part').exists(), isFalse);
        expect(progress.last, (bytes.length, bytes.length));

        await target.delete();
        final cancelToken = CancelToken();
        await expectLater(
          repository.downloadAttachmentToFile(
            message,
            target.path,
            cancelToken: cancelToken,
            onReceiveProgress: (received, _) {
              if (received > 0) cancelToken.cancel('test-cancel');
            },
          ),
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        expect(await target.exists(), isFalse);
        expect(await File('${target.path}.part').exists(), isFalse);
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'multi-image preparation encrypts each result before preparing the next',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        const MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '测试成员',
          username: 'term.member1',
          policySignatureKey: '',
          imApiUrl: 'http://127.0.0.1:1',
          oaApiUrl: '',
        ),
      );
      final store = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => inMemoryDatabasePath,
      );
      final queueDirectory = await Directory.systemTemp.createTemp(
        'im-image-preparation-',
      );
      final repository = ImRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
        outboxFileStore: ImOutboxFileStore(
          keyLoader: sessionStore.readOrCreateImCacheKey,
          directoryLoader: () async => queueDirectory,
        ),
      );

      Future<int> queuedFileCount() async => queueDirectory
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.imq'))
          .length;

      try {
        final preparedIndexes = <int>[];
        final message = await repository.sendPreparedImages(
          conversationId: 'conversation-1',
          count: 3,
          prepare: (index) async {
            expect(await queuedFileCount(), index);
            preparedIndexes.add(index);
            return (
              fileName: 'image-$index.jpg',
              bytes: Uint8List.fromList([index + 1]),
              contentType: 'image/jpeg',
            );
          },
        );
        expect(preparedIndexes, [0, 1, 2]);
        expect(message.localStatus, ImLocalMessageStatus.pending);
        expect(message.images, hasLength(3));
        expect(await queuedFileCount(), 3);

        await expectLater(
          repository.sendPreparedImages(
            conversationId: 'conversation-2',
            count: 3,
            prepare: (index) async {
              if (index == 1) throw StateError('prepare failed');
              return (
                fileName: 'failed-$index.jpg',
                bytes: Uint8List.fromList([9]),
                contentType: 'image/jpeg',
              );
            },
          ),
          throwsStateError,
        );
        expect(await queuedFileCount(), 3);
      } finally {
        await store.close();
        await queueDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'original image streams are encrypted sequentially and rollback on failure',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        const MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '测试成员',
          username: 'term.member1',
          policySignatureKey: '',
          imApiUrl: 'http://127.0.0.1:1',
          oaApiUrl: '',
        ),
      );
      final store = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => inMemoryDatabasePath,
      );
      final queueDirectory = await Directory.systemTemp.createTemp(
        'im-original-image-streams-',
      );
      final repository = ImRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
        outboxFileStore: ImOutboxFileStore(
          keyLoader: sessionStore.readOrCreateImCacheKey,
          directoryLoader: () async => queueDirectory,
        ),
      );

      Future<int> queuedFileCount() async => queueDirectory
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.imq'))
          .length;

      try {
        final opened = <int>[];
        final message = await repository.sendPreparedImageStreams(
          conversationId: 'conversation-1',
          count: 2,
          prepare: (index) async {
            expect(await queuedFileCount(), index);
            final bytes = [index + 1, index + 11, index + 21];
            return (
              fileName: 'animated-$index.gif',
              length: bytes.length,
              contentType: 'image/gif',
              openRead: () async* {
                opened.add(index);
                yield bytes.sublist(0, 1);
                yield bytes.sublist(1);
              },
            );
          },
        );
        expect(opened, [0, 1]);
        expect(message.localStatus, ImLocalMessageStatus.pending);
        expect(message.images, hasLength(2));
        expect(await queuedFileCount(), 2);

        await expectLater(
          repository.sendPreparedImageStreams(
            conversationId: 'conversation-2',
            count: 2,
            prepare: (index) async {
              if (index == 1) throw StateError('prepare failed');
              return (
                fileName: 'failed.gif',
                length: 3,
                contentType: 'image/gif',
                openRead: () => Stream<List<int>>.value(const [1, 2, 3]),
              );
            },
          ),
          throwsStateError,
        );
        expect(await queuedFileCount(), 2);
      } finally {
        await store.close();
        await queueDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'outbox error identifies upload or send stage without leaking request data',
    () {
      for (final entry in <String, String>{
        '/api/im/upload/video': '视频上传',
        '/api/im/upload/audio': '音频上传',
        '/api/im/conversations/test/media-messages': '媒体消息提交',
        '/api/im/conversations/test/images': '图片发送',
        '/api/im/conversations/test/attachments': '文件发送',
        '/api/im/conversations/test/messages': '消息发送',
        '/private/path': '消息服务请求',
      }.entries) {
        final request = RequestOptions(
          path: 'https://private.invalid${entry.key}?token=secret',
          headers: {'Authorization': 'private-test-value'},
        );
        final text = imOutboxFailureText(
          DioException(
            requestOptions: request,
            type: DioExceptionType.badResponse,
            response: Response<Object?>(
              requestOptions: request,
              statusCode: 500,
              data: {'private': 'sensitive-test-body'},
            ),
          ),
        );
        expect(text, '${entry.value}失败（HTTP 500）');
      }
    },
  );

  test('outbox retries network failures but exposes permanent 4xx', () {
    final request = RequestOptions(path: '/api/im/messages');
    expect(
      isTransientImOutboxFailure(
        DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      ),
      isTrue,
    );
    expect(
      isTransientImOutboxFailure(
        DioException(
          requestOptions: request,
          response: Response<Object?>(requestOptions: request, statusCode: 503),
          type: DioExceptionType.badResponse,
        ),
      ),
      isTrue,
    );
    expect(
      isTransientImOutboxFailure(
        DioException(
          requestOptions: request,
          response: Response<Object?>(requestOptions: request, statusCode: 400),
          type: DioExceptionType.badResponse,
        ),
      ),
      isFalse,
    );
  });

  test('queued image survives store restart with protected preview', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final sessionStore = SecureSessionStore();
    await sessionStore.saveSession(
      const MobileSession(
        accessToken: 'token',
        deviceId: 'device-1',
        userId: 'member-1',
        displayName: '测试成员',
        username: 'term.member1',
        policySignatureKey: '',
        imApiUrl: 'http://127.0.0.1:1',
        oaApiUrl: '',
      ),
    );
    final directory = await Directory.systemTemp.createTemp(
      'im-outbox-restart-',
    );
    final databasePath = path.join(directory.path, 'im.db');
    final fileStore = ImOutboxFileStore(
      keyLoader: sessionStore.readOrCreateImCacheKey,
      directoryLoader: () async => Directory(path.join(directory.path, 'q')),
    );
    var store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => databasePath,
    );
    var repository = ImRepository(
      CollaborationClient(sessionStore),
      sessionStore,
      store,
      outboxFileStore: fileStore,
    );
    final bytes = Uint8List.fromList([11, 12, 13, 14]);

    try {
      final local = await repository.sendImages(
        conversationId: 'conversation-1',
        files: [
          (fileName: 'restart.jpg', bytes: bytes, contentType: 'image/jpeg'),
        ],
      );
      final imageId = local.images.single.id;
      await store.close();

      store = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => databasePath,
      );
      repository = ImRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
        outboxFileStore: fileStore,
      );
      final restored = await store.readMessages('member-1', 'conversation-1');
      expect(restored, hasLength(1));
      expect(restored.single.localStatus, ImLocalMessageStatus.pending);
      expect(restored.single.images.single.id, imageId);
      expect(
        await repository.downloadMessageImage(restored.single.id, imageId),
        bytes,
      );
      final due = await store.dueOutbox('member-1');
      expect(due.single.kind, 'image');
      expect(due.single.mediaFiles, hasLength(1));
    } finally {
      await store.close();
      await directory.delete(recursive: true);
    }
  });
}

class _RealHttpOverrides extends HttpOverrides {}

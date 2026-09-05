import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_outbox_file_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'video send uploads and persists its generated cover metadata',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final calls = <String>[];
      Map<String, Object?>? mediaPayload;

      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'POST' &&
            request.uri.path == '/api/im/upload/video') {
          await request.drain<void>();
          request.response.write(
            jsonEncode({
              'objectId': 'video-object',
              'fileName': 'AI-UAT-video.mp4',
              'contentType': 'video/mp4',
              'size': 4,
              'sha256': 'video-sha256',
              'width': 640,
              'height': 360,
              'durationSeconds': 1.25,
            }),
          );
        } else if (request.method == 'POST' &&
            request.uri.path == '/api/im/upload/picture') {
          await request.drain<void>();
          request.response.write(
            jsonEncode({
              'objectId': 'cover-object',
              'fileName': 'AI-UAT-video-cover.jpg',
              'contentType': 'image/jpeg',
              'size': 3,
              'sha256': 'cover-sha256',
              'width': 320,
              'height': 180,
            }),
          );
        } else if (request.method == 'POST' &&
            request.uri.path ==
                '/api/im/conversations/conversation-1/media-messages') {
          mediaPayload = (jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map).cast<String, Object?>();
          final attachment =
              ((mediaPayload!['attachments'] as List).single as Map)
                  .cast<String, Object?>();
          request.response.write(
            jsonEncode({
              'id': 'message-1',
              'conversationId': 'conversation-1',
              'sequence': 10,
              'senderId': 'member-1',
              'content': '',
              'kind': 'video',
              'attachments': [
                {
                  'id': 'attachment-1',
                  'type': 'video',
                  'fileName': attachment['fileName'],
                  'contentType': attachment['contentType'],
                  'size': attachment['size'],
                  'sha256': attachment['sha256'],
                  'width': attachment['width'],
                  'height': attachment['height'],
                  'coverObjectId': attachment['coverObjectId'],
                  'coverContentType': attachment['coverContentType'],
                  'coverSize': attachment['coverSize'],
                  'coverSha256': attachment['coverSha256'],
                  'coverWidth': attachment['coverWidth'],
                  'coverHeight': attachment['coverHeight'],
                  'durationSeconds': attachment['durationSeconds'],
                },
              ],
            }),
          );
        } else if (request.method == 'GET' &&
            request.uri.path == '/api/im/bootstrap') {
          request.response.write(
            jsonEncode({
              'currentMember': {
                'id': 'member-1',
                'userName': 'term.member1',
                'displayName': '测试成员',
                'isOnline': true,
              },
              'contacts': <Object?>[],
              'conversations': <Object?>[],
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      FlutterSecureStorage.setMockInitialValues({});
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '测试成员',
          username: 'term.member1',
          policySignatureKey: '',
          imApiUrl: 'http://${server.address.address}:${server.port}',
          oaApiUrl: '',
        ),
      );
      final store = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => inMemoryDatabasePath,
      );
      final queueDirectory = await Directory.systemTemp.createTemp(
        'im-media-outbox-',
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

      try {
        var mediaOpens = 0;
        final local = await repository.sendMediaStream(
          conversationId: 'conversation-1',
          kind: 'video',
          fileName: 'AI-UAT-video.mp4',
          length: 4,
          openRead: () {
            mediaOpens += 1;
            return Stream<List<int>>.fromIterable(const [
              [0, 1],
              [2, 3],
            ]);
          },
          contentType: 'video/mp4',
          coverBytes: Uint8List.fromList([4, 5, 6]),
          coverWidth: 320,
          coverHeight: 180,
        );

        expect(local.localStatus, ImLocalMessageStatus.pending);
        expect(local.kind, 'video');
        expect(local.attachments.single.coverWidth, 320);
        expect(mediaOpens, 1);
        expect(calls, isEmpty);
        expect(await store.dueOutbox('member-1'), hasLength(1));
        expect(
          await repository.readQueuedMediaPreview(local.attachments.single.id),
          Uint8List.fromList([4, 5, 6]),
        );

        final flushed = await repository.flushOutboxDetailed();
        expect(flushed.deliveredCount, 1);

        expect(calls.take(3), [
          'POST /api/im/upload/video',
          'POST /api/im/upload/picture',
          'POST /api/im/conversations/conversation-1/media-messages',
        ]);
        final sentAttachment =
            ((mediaPayload!['attachments'] as List).single as Map)
                .cast<String, Object?>();
        expect(sentAttachment['coverObjectId'], 'cover-object');
        expect(sentAttachment['coverContentType'], 'image/jpeg');
        expect(sentAttachment['coverSize'], 3);
        expect(sentAttachment['coverSha256'], 'cover-sha256');
        expect(sentAttachment['durationSeconds'], 1.25);
        final cached = await store.readMessages('member-1', 'conversation-1');
        final attachment = cached.single.attachments.single;
        expect(attachment.coverObjectId, 'cover-object');
        expect(attachment.coverContentType, 'image/jpeg');
        expect(attachment.coverSize, 3);
        expect(attachment.coverSha256, 'cover-sha256');
        expect(attachment.coverWidth, 320);
        expect(attachment.coverHeight, 180);
        expect(await store.dueOutbox('member-1'), isEmpty);
        final queueFiles = await queueDirectory
            .list(recursive: true)
            .where((entity) => entity is File && entity.path.endsWith('.imq'))
            .toList();
        expect(queueFiles, isEmpty);
      } finally {
        await store.close();
        await queueDirectory.delete(recursive: true);
        await server.close(force: true);
        HttpOverrides.global = null;
      }
    },
  );

  test('queued images flush once and replace the local message', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <String>[];
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' &&
          request.uri.path == '/api/im/conversations/conversation-1/images') {
        await request.drain<void>();
        request.response.write(
          jsonEncode({
            'id': 'image-message-1',
            'conversationId': 'conversation-1',
            'sequence': 11,
            'senderId': 'member-1',
            'clientMessageId': 'server-confirmed-client-id',
            'content': '',
            'kind': 'image',
            'images': [
              {
                'id': 'image-1',
                'fileName': 'AI-UAT-image.jpg',
                'contentType': 'image/jpeg',
                'size': 4,
                'sha256': 'image-sha256',
              },
            ],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    FlutterSecureStorage.setMockInitialValues({});
    final sessionStore = SecureSessionStore();
    await sessionStore.saveSession(
      MobileSession(
        accessToken: 'token',
        deviceId: 'device-1',
        userId: 'member-1',
        displayName: '测试成员',
        username: 'term.member1',
        policySignatureKey: '',
        imApiUrl: 'http://${server.address.address}:${server.port}',
        oaApiUrl: '',
      ),
    );
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    final queueDirectory = await Directory.systemTemp.createTemp(
      'im-image-outbox-',
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

    try {
      final local = await repository.sendImages(
        conversationId: 'conversation-1',
        files: [
          (
            fileName: 'AI-UAT-image.jpg',
            bytes: Uint8List.fromList([1, 2, 3, 4]),
            contentType: 'image/jpeg',
          ),
        ],
      );
      expect(local.localStatus, ImLocalMessageStatus.pending);
      expect(calls, isEmpty);

      final flushed = await repository.flushOutboxDetailed();
      expect(flushed.deliveredCount, 1);
      expect(calls, ['POST /api/im/conversations/conversation-1/images']);
      final cached = await store.readMessages('member-1', 'conversation-1');
      expect(cached, hasLength(1));
      expect(cached.single.id, 'image-message-1');
      expect(cached.single.localStatus, ImLocalMessageStatus.sent);
      expect(cached.single.images.single.id, 'image-1');
      expect(await store.dueOutbox('member-1'), isEmpty);
      final queueFiles = await queueDirectory
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.imq'))
          .toList();
      expect(queueFiles, isEmpty);
    } finally {
      await store.close();
      await queueDirectory.delete(recursive: true);
      await server.close(force: true);
      HttpOverrides.global = null;
    }
  });

  test('queued file streams once and deletes its protected payload', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <String>[];
    final uploadBodies = <List<int>>[];
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' &&
          request.uri.path ==
              '/api/im/conversations/conversation-1/attachments') {
        uploadBodies.add(
          await request.fold<List<int>>(
            <int>[],
            (bytes, chunk) => bytes..addAll(chunk),
          ),
        );
        request.response.write(
          jsonEncode({
            'id': 'file-message-1',
            'conversationId': 'conversation-1',
            'sequence': 12,
            'senderId': 'member-1',
            'content': '附件：AI-UAT-report.txt',
            'kind': 'file',
            'attachmentName': 'AI-UAT-report.txt',
            'attachmentSize': 4,
            'attachmentContentType': 'text/plain',
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    FlutterSecureStorage.setMockInitialValues({});
    final sessionStore = SecureSessionStore();
    await sessionStore.saveSession(
      MobileSession(
        accessToken: 'token',
        deviceId: 'device-1',
        userId: 'member-1',
        displayName: '测试成员',
        username: 'term.member1',
        policySignatureKey: '',
        imApiUrl: 'http://${server.address.address}:${server.port}',
        oaApiUrl: '',
      ),
    );
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    final queueDirectory = await Directory.systemTemp.createTemp(
      'im-file-outbox-',
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

    try {
      var fileOpens = 0;
      final local = await repository.sendAttachmentStream(
        conversationId: 'conversation-1',
        fileName: 'AI-UAT-report.txt',
        length: 4,
        openRead: () {
          fileOpens += 1;
          return Stream<List<int>>.fromIterable(const [
            [65, 66],
            [67, 68],
          ]);
        },
        contentType: 'text/plain',
      );
      expect(local.localStatus, ImLocalMessageStatus.pending);
      expect(fileOpens, 1);
      expect(calls, isEmpty);
      final item = (await store.dueOutbox('member-1')).single;
      expect(item.attachmentBytes, isEmpty);
      expect(item.mediaFiles.single.role, 'file');

      final flushed = await repository.flushOutboxDetailed();
      expect(flushed.deliveredCount, 1);
      expect(calls, ['POST /api/im/conversations/conversation-1/attachments']);
      expect(uploadBodies.single, containsAllInOrder([65, 66, 67, 68]));
      final cached = await store.readMessages('member-1', 'conversation-1');
      expect(cached.single.id, 'file-message-1');
      expect(cached.single.localStatus, ImLocalMessageStatus.sent);
      expect(await store.dueOutbox('member-1'), isEmpty);
      final queueFiles = await queueDirectory
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.imq'))
          .toList();
      expect(queueFiles, isEmpty);
    } finally {
      await store.close();
      await queueDirectory.delete(recursive: true);
      await server.close(force: true);
      HttpOverrides.global = null;
    }
  });
}

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

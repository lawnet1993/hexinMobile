import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
      final repository = ImRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
      );

      try {
        final message = await repository.sendMedia(
          conversationId: 'conversation-1',
          kind: 'video',
          fileName: 'AI-UAT-video.mp4',
          bytes: Uint8List.fromList([0, 1, 2, 3]),
          contentType: 'video/mp4',
          coverBytes: Uint8List.fromList([4, 5, 6]),
          coverWidth: 320,
          coverHeight: 180,
        );

        final attachment = message.attachments.single;
        expect(calls.take(3), [
          'POST /api/im/upload/video',
          'POST /api/im/upload/picture',
          'POST /api/im/conversations/conversation-1/media-messages',
        ]);
        expect(attachment.coverObjectId, 'cover-object');
        expect(attachment.coverWidth, 320);
        expect(attachment.coverHeight, 180);
        final sentAttachment =
            ((mediaPayload!['attachments'] as List).single as Map)
                .cast<String, Object?>();
        expect(sentAttachment['coverObjectId'], 'cover-object');
        expect(sentAttachment['durationSeconds'], 1.25);
        final cached = await store.readMessages('member-1', 'conversation-1');
        expect(cached.single.attachments.single.coverObjectId, 'cover-object');
      } finally {
        await store.close();
        await server.close(force: true);
        HttpOverrides.global = null;
      }
    },
  );
}

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

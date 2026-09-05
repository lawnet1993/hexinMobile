import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/attachment_preview_repository.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/attachment_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'preview lifecycle uses mobile identity and validates a 206 range',
    () async {
      final calls = <String>[];
      late HttpServer server;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        calls.add('${request.method} ${request.uri.path}');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer token',
        );
        expect(request.headers.value('X-Device-Id'), 'mobile-device');
        expect(request.headers.value('X-Terminal-Account-Id'), 'member-1');
        if (request.method == 'POST' &&
            request.uri.path.endsWith('/preview-sessions')) {
          expect(request.uri.queryParameters['cover'], 'true');
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'sessionId': 'session-1',
              'status': 'ready',
              'previewKind': 'image',
              'contentType': 'image/jpeg',
              'previewUrl': '/api/im/attachment-preview-sessions/session-1/content?ticket=opaque',
              'expiresAt': '2026-09-05T14:00:00Z',
              'renewAfterSeconds': 120,
              'originalDownloadAllowed': true,
              'originalDownloadUrl': '/api/im/media-attachments/media-1',
            }),
          );
        } else if (request.method == 'GET' &&
            request.uri.path.endsWith('/content')) {
          expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=0-3');
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-3/10',
          );
          request.response.add([1, 2, 3, 4]);
        } else if (request.method == 'POST' &&
            request.uri.path.endsWith('/renew')) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'sessionId': 'session-1',
              'expiresAt': '2026-09-05T14:02:00Z',
              'renewAfterSeconds': 90,
            }),
          );
        } else if (request.method == 'DELETE') {
          request.response.statusCode = HttpStatus.noContent;
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final fixture = await _repository(server);
      final session = await fixture.repository.createImMediaSession(
        'media-1',
        cover: true,
      );
      expect(session.ready, isTrue);
      expect(session.previewKind, 'image');
      expect(session.originalDownloadAllowed, isTrue);
      final chunk = await fixture.repository.readSingleRange(
        session: session,
        start: 0,
        length: 4,
        expectedTotalLength: 10,
      );
      expect(chunk.bytes, [1, 2, 3, 4]);
      expect(chunk.range.start, 0);
      expect(chunk.range.end, 3);
      expect(chunk.range.totalLength, 10);
      expect(chunk.completeResponse, isFalse);
      final renewed = await fixture.repository.renewImSession(session);
      expect(renewed.renewAfterSeconds, 90);
      await fixture.repository.closeImSession(renewed);
      expect(calls, [
        'POST /api/im/media-attachments/media-1/preview-sessions',
        'GET /api/im/attachment-preview-sessions/session-1/content',
        'POST /api/im/attachment-preview-sessions/session-1/renew',
        'DELETE /api/im/attachment-preview-sessions/session-1',
      ]);
    },
  );

  test(
    'range protocol rejects malformed, oversized and server-error responses',
    () async {
      var responseMode = 'malformed';
      var contentRequests = 0;
      late HttpServer server;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'POST') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'sessionId': 'session-2',
              'status': 'ready',
              'previewKind': 'video',
              'contentType': 'video/mp4',
              'previewUrl': '/api/im/attachment-preview-sessions/session-2/content?ticket=opaque',
              'renewAfterSeconds': 120,
              'originalDownloadAllowed': false,
            }),
          );
        } else {
          contentRequests++;
          if (responseMode == 'malformed') {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes 1-4/10',
            );
            request.response.add([1, 2, 3, 4]);
          } else {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'code': 'preview_failed'}));
          }
        }
        await request.response.close();
      });
      final fixture = await _repository(server);
      final session = await fixture.repository.createImMediaSession('media-2');
      await expectLater(
        fixture.repository.readSingleRange(
          session: session,
          start: 0,
          length: 4,
          expectedTotalLength: 10,
        ),
        throwsA(isA<AttachmentPreviewProtocolException>()),
      );
      responseMode = 'server-error';
      await expectLater(
        fixture.repository.readSingleRange(
          session: session,
          start: 0,
          length: 4,
          expectedTotalLength: 10,
        ),
        throwsA(
          isA<AttachmentPreviewProtocolException>().having(
            (error) => error.statusCode,
            'status',
            500,
          ),
        ),
      );
      await expectLater(
        fixture.repository.readSingleRange(
          session: session,
          start: 0,
          length: attachmentPreviewChunkBytes + 1,
          expectedTotalLength: 10,
        ),
        throwsA(isA<AttachmentPreviewProtocolException>()),
      );
      expect(contentRequests, 2);
    },
  );

  test(
    '416 exposes total length and a full 200 is accepted only from zero',
    () async {
      var mode = 'unsatisfied';
      late HttpServer server;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.method == 'POST') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'sessionId': 'session-3',
              'status': 'ready',
              'previewKind': 'video',
              'contentType': 'video/mp4',
              'previewUrl': '/api/im/attachment-preview-sessions/session-3/content?ticket=opaque',
              'renewAfterSeconds': 120,
              'originalDownloadAllowed': false,
            }),
          );
        } else if (mode == 'unsatisfied') {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */4',
          );
        } else {
          request.response.statusCode = HttpStatus.ok;
          request.response.add([1, 2, 3, 4]);
        }
        await request.response.close();
      });
      final fixture = await _repository(server);
      final session = await fixture.repository.createImMediaSession('media-3');
      await expectLater(
        fixture.repository.readSingleRange(
          session: session,
          start: 4,
          length: 4,
          expectedTotalLength: 4,
        ),
        throwsA(
          isA<AttachmentRangeNotSatisfiable>().having(
            (error) => error.totalLength,
            'total length',
            4,
          ),
        ),
      );
      mode = 'full';
      final complete = await fixture.repository.readSingleRange(
        session: session,
        start: 0,
        length: 4,
        expectedTotalLength: 4,
      );
      expect(complete.completeResponse, isTrue);
      expect(complete.bytes, [1, 2, 3, 4]);
      await expectLater(
        fixture.repository.readSingleRange(
          session: session,
          start: 1,
          length: 3,
          expectedTotalLength: 4,
        ),
        throwsA(isA<AttachmentPreviewProtocolException>()),
      );
    },
  );

  test('ready response rejects absolute or mismatched ticket URLs', () async {
    late HttpServer server;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'sessionId': 'session-4',
          'status': 'ready',
          'previewKind': 'video',
          'contentType': 'video/mp4',
          'previewUrl': 'https://outside.invalid/content?ticket=opaque',
          'renewAfterSeconds': 120,
          'originalDownloadAllowed': false,
        }),
      );
      await request.response.close();
    });
    final fixture = await _repository(server);
    await expectLater(
      fixture.repository.createImMediaSession('media-4'),
      throwsA(isA<AttachmentPreviewProtocolException>()),
    );
  });
}

Future<({AttachmentPreviewRepository repository, SecureSessionStore store})>
_repository(HttpServer server) async {
  HttpOverrides.global = _RealHttpOverrides();
  addTearDown(() => HttpOverrides.global = null);
  FlutterSecureStorage.setMockInitialValues({});
  final store = SecureSessionStore();
  await store.saveSession(
    MobileSession(
      accessToken: 'token',
      deviceId: 'mobile-device',
      installationId: 'mobile-installation',
      userId: 'member-1',
      displayName: 'Fixture',
      username: 'fixture',
      policySignatureKey: '',
      imApiUrl: 'http://${server.address.address}:${server.port}',
      oaApiUrl: '',
    ),
  );
  return (
    repository: AttachmentPreviewRepository(CollaborationClient(store), store),
    store: store,
  );
}

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

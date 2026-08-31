import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'notification paging uses the desktop endpoint and cursor contract',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final directory = await Directory.systemTemp.createTemp('oa-page-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Uri? requestedUri;
      server.listen((request) async {
        requestedUri = request.uri;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'items': [
              {
                'id': 'notification-2',
                'requestId': 'approval-2',
                'category': 'approval',
                'type': 'pending',
                'title': '第二页通知',
                'body': '待处理',
                'importance': 'normal',
                'action': 'open',
                'isRead': false,
                'createdAt': '2026-08-25T08:00:00Z',
              },
            ],
            'nextCursor': 'cursor-3',
            'hasMore': true,
          }),
        );
        await request.response.close();
      });

      FlutterSecureStorage.setMockInitialValues({});
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '测试终端',
          username: 'qa.term',
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: 'http://${server.address.address}:${server.port}',
        ),
      );
      final store = OaLocalStore.withOptions(
        databaseFactoryFfi,
        () async => '${directory.path}/oa.db',
        const PlainImCacheCipher(),
      );
      final repository = OaRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
      );

      try {
        final page = await repository.notificationPage(
          cursor: 'cursor-2',
          unreadOnly: true,
          take: 60,
        );
        expect(requestedUri?.path, '/api/oa/notifications/page');
        expect(requestedUri?.queryParameters, {
          'take': '60',
          'unreadOnly': 'true',
          'cursor': 'cursor-2',
        });
        expect(page.items.single.title, '第二页通知');
        expect(page.nextCursor, 'cursor-3');
        expect(page.hasMore, isTrue);
      } finally {
        await store.close();
        await server.close(force: true);
        await directory.delete(recursive: true);
        HttpOverrides.global = null;
      }
    },
  );
}

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}

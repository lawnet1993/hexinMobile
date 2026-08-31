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

  test(
    'cached first page restores offline with unread and cursor state',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('oa-page-cache-');
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        const MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '测试终端',
          username: 'qa.term',
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: 'http://127.0.0.1:9',
        ),
      );
      final store = OaLocalStore.withOptions(
        databaseFactoryFfi,
        () async => '${directory.path}/oa.db',
        const PlainImCacheCipher(),
      );
      await store.writeObject(
        'member-1',
        OaLocalStore.notificationPageCacheKey,
        {
          'items': [
            _notificationJson('notification-unread', isRead: false),
            _notificationJson('notification-read', isRead: true),
          ],
          'nextCursor': 'cursor-2',
          'hasMore': true,
        },
      );
      final repository = OaRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        store,
      );

      try {
        final page = await repository.notificationPageCacheFirst(
          unreadOnly: true,
        );
        expect(page.items.map((item) => item.id), ['notification-unread']);
        expect(page.nextCursor, 'cursor-2');
        expect(page.hasMore, isTrue);
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('mark read keeps the local notification page available', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final directory = await Directory.systemTemp.createTemp('oa-page-read-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/oa/notifications/notification-1/read');
      request.response.statusCode = HttpStatus.noContent;
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
    final cachedItems = [
      _notificationJson('notification-1', isRead: false),
      _notificationJson('notification-2', isRead: false),
    ];
    await store.writeList(
      'member-1',
      OaLocalStore.notificationsCacheKey,
      cachedItems,
    );
    await store.writeObject('member-1', OaLocalStore.notificationPageCacheKey, {
      'items': cachedItems,
      'nextCursor': null,
      'hasMore': false,
    });
    final repository = OaRepository(
      CollaborationClient(sessionStore),
      sessionStore,
      store,
    );

    try {
      await repository.markNotificationRead('notification-1');
      final page = await repository.notificationPageCacheFirst();
      expect(page.items[0].isRead, isTrue);
      expect(page.items[0].readAt, isNotNull);
      expect(page.items[1].isRead, isFalse);
    } finally {
      await store.close();
      await server.close(force: true);
      await directory.delete(recursive: true);
      HttpOverrides.global = null;
    }
  });
}

Map<String, Object?> _notificationJson(String id, {required bool isRead}) => {
  'id': id,
  'requestId': 'approval-$id',
  'category': 'approval',
  'type': 'pending',
  'title': id,
  'body': '待处理',
  'importance': 'normal',
  'action': 'open',
  'isRead': isRead,
  'createdAt': '2026-08-25T08:00:00Z',
  'targetKind': 'oa_approval',
  'targetId': 'approval-$id',
};

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}

import 'dart:async';
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
  late Directory directory;
  late OaLocalStore store;
  late SecureSessionStore sessions;
  late HttpServer server;
  late OaRepository repository;
  late List<String> posted;
  late int responseStatus;
  Completer<void>? gate;

  OaLocalStore openStore() => OaLocalStore.withOptions(
    databaseFactoryFfi,
    () async => '${directory.path}/oa.db',
    const PlainImCacheCipher(),
  );
  Future<void> login(String account) => sessions.saveSession(
    MobileSession(
      accessToken: 'fixture-token',
      deviceId: 'fixture-device',
      userId: account,
      displayName: account,
      username: account,
      policySignatureKey: '',
      imApiUrl: '',
      oaApiUrl: 'http://${server.address.address}:${server.port}',
    ),
  );
  setUp(() async {
    HttpOverrides.global = _RealHttp();
    directory = await Directory.systemTemp.createTemp('oa-read-receipts-');
    store = openStore();
    posted = [];
    responseStatus = 204;
    gate = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'POST') {
        posted.add(request.uri.path);
        if (gate != null) await gate!.future;
        request.response.statusCode = responseStatus;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path.endsWith('bootstrap')
                ? {'notifications': notices}
                : {'items': notices, 'hasMore': false, 'nextCursor': null},
          ),
        );
      }
      await request.response.close();
    });
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SecureSessionStore();
    await login('account-a');
    repository = OaRepository(CollaborationClient(sessions), sessions, store);
    await store.writeList(
      'account-a',
      OaLocalStore.notificationsCacheKey,
      notices,
    );
    await store.writeObject(
      'account-a',
      OaLocalStore.notificationPageCacheKey,
      {'items': notices, 'hasMore': false},
    );
    await store.writeObject('account-a', OaLocalStore.bootstrapCacheKey, {
      'notifications': notices,
    });
  });
  tearDown(() async {
    if (gate != null && !gate!.isCompleted) gate!.complete();
    await server.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
    HttpOverrides.global = null;
  });

  test(
    'reading commits locally without network and survives cold reopen',
    () async {
      await repository.markNotificationRead('notice-1');
      expect(posted, isEmpty);
      expect(await repository.pendingNotificationReadCount(), 1);
      expect(await repository.outbox(), isEmpty);
      final before = await repository.notificationPageCacheFirst();
      expect(before.items.map((e) => e.isRead), [true, false]);
      final originalTime = before.items.first.readAt;
      await store.close();
      store = openStore();
      repository = OaRepository(CollaborationClient(sessions), sessions, store);
      await repository.markNotificationRead('notice-1');
      expect(await repository.pendingNotificationReadCount(), 1);
      final after = await repository.notificationPageCacheFirst();
      expect(after.items.first.readAt, originalTime);
      expect(after.items.map((e) => e.isRead), [true, false]);
      expect(
        (await repository.bootstrapCacheFirst()).notifications.first.isRead,
        isTrue,
      );
      expect(posted, isEmpty);
    },
  );

  test(
    'late snapshots and fresh server pages cannot resurrect a local read',
    () async {
      await repository.markNotificationRead('notice-1');
      await store.applySyncBatch(
        accountId: 'account-a',
        events: [],
        refreshedCaches: {
          OaLocalStore.bootstrapCacheKey: jsonEncode({
            'notifications': notices,
          }),
          OaLocalStore.notificationPageCacheKey: jsonEncode({'items': notices}),
          OaLocalStore.notificationsCacheKey: jsonEncode(notices),
        },
      );
      expect(
        (await repository.bootstrapCacheFirst()).notifications.first.isRead,
        isTrue,
      );
      expect(
        (await repository.refreshBootstrap()).notifications.first.isRead,
        isTrue,
      );
      expect((await repository.notificationsCacheFirst()).first.isRead, isTrue);
      expect((await repository.notificationPage()).items.first.isRead, isTrue);
      expect(
        (await repository.notificationPage(unreadOnly: true)).items
            .map((e) => e.id),
        ['notice-2'],
      );
    },
  );

  test(
    'ACK clears only pending receipt and old snapshots remain read',
    () async {
      await repository.markNotificationRead('notice-1');
      expect(await repository.flushNotificationReads(), 1);
      expect(posted, ['/api/oa/notifications/notice-1/read']);
      expect(await repository.pendingNotificationReadCount(), 0);
      expect((await repository.notificationPage()).items.first.isRead, isTrue);
      await repository.markNotificationRead('notice-1');
      expect(await repository.flushNotificationReads(), 0);
      expect(posted.length, 1);
      expect(
        (await repository.notificationPageCacheFirst()).items[1].isRead,
        isFalse,
      );
    },
  );

  test(
    'transient failure backs off and explicit retry delivers original receipt',
    () async {
      responseStatus = 500;
      await repository.markNotificationRead('notice-1');
      expect(await repository.flushNotificationReads(), 0);
      expect(await repository.pendingNotificationReadCount(), 1);
      expect(await repository.flushNotificationReads(), 0);
      expect(posted.length, 1);
      responseStatus = 204;
      expect(await repository.flushNotificationReads(retryNow: true), 1);
      expect(posted, List.filled(2, '/api/oa/notifications/notice-1/read'));
      expect(await repository.pendingNotificationReadCount(), 0);
    },
  );

  test('receipts and projections are isolated by account', () async {
    await repository.markNotificationRead('notice-1');
    await login('account-b');
    expect(await repository.pendingNotificationReadCount(), 0);
    expect(await repository.flushNotificationReads(), 0);
    expect((await repository.notificationPage()).items.first.isRead, isFalse);
    expect(posted, isEmpty);
    await login('account-a');
    expect(await repository.pendingNotificationReadCount(), 1);
    expect(await repository.flushOutbox(), 1);
    expect(await repository.outbox(), isEmpty);
  });

  test(
    'concurrent flush is coalesced and unread new arrivals are untouched',
    () async {
      await repository.markNotificationRead('notice-1');
      gate = Completer<void>();
      final a = repository.flushNotificationReads();
      final b = repository.flushNotificationReads();
      while (posted.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(posted.length, 1);
      gate!.complete();
      expect(await a, 1);
      expect(await b, 1);
      expect(posted.length, 1);
      expect((await repository.notificationPage()).items[1].isRead, isFalse);
    },
  );

  test(
    'permission failure stays visible but is not automatically retried',
    () async {
      responseStatus = 403;
      await repository.markNotificationRead('notice-1');
      expect(await repository.flushNotificationReads(), 0);
      expect(await repository.pendingNotificationReadCount(), 1);
      expect(await repository.flushNotificationReads(), 0);
      expect(posted.length, 1);
      responseStatus = 204;
      expect(await repository.flushNotificationReads(retryNow: true), 1);
    },
  );

  test(
    'version 2 upgrade keeps existing cache and adds independent receipts',
    () async {
      final oldPath = '${directory.path}/old.db';
      final old = await databaseFactoryFfi.openDatabase(
        oldPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE oa_cache(account_id TEXT, cache_key TEXT, payload_json TEXT, updated_at TEXT)',
            );
            await db.insert('oa_cache', {
              'account_id': 'account-a',
              'cache_key': OaLocalStore.notificationsCacheKey,
              'payload_json': jsonEncode(notices),
              'updated_at': '2026-09-02T00:00:00Z',
            });
          },
        ),
      );
      await old.close();
      final upgraded = OaLocalStore.withOptions(
        databaseFactoryFfi,
        () async => oldPath,
        const PlainImCacheCipher(),
      );
      try {
        await upgraded.enqueueNotificationRead('account-a', 'notice-1');
        final result = await upgraded.readList(
          'account-a',
          OaLocalStore.notificationsCacheKey,
        );
        expect((result![0] as Map)['isRead'], isTrue);
        expect((result[1] as Map)['isRead'], isFalse);
        expect(await upgraded.pendingNotificationReadCount('account-a'), 1);
      } finally {
        await upgraded.close();
      }
    },
  );
}

final notices = List<Object?>.generate(
  2,
  (i) => <String, Object?>{
    'id': 'notice-${i + 1}',
    'requestId': 'approval-${i + 1}',
    'category': 'approval',
    'type': 'approval.updated',
    'title': 'AI-UAT notice ${i + 1}',
    'body': '',
    'isRead': false,
    'createdAt': '2026-09-02T00:00:00Z',
  },
);

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionTimeout = const Duration(seconds: 5);
}

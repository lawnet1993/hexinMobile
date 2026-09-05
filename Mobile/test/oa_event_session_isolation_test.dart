import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _paths = [
  '/api/oa/sync/events',
  '/api/oa/notifications/page',
  '/api/oa/bootstrap',
  '/api/oa/app-catalog',
  '/api/oa/attendance/overview',
];
const _keys = [
  OaLocalStore.bootstrapCacheKey,
  OaLocalStore.catalogCacheKey,
  OaLocalStore.notificationPageCacheKey,
  OaLocalStore.attendanceCacheKey,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late SecureSessionStore sessions;
  late OaLocalStore store;
  late OaRepository repository;
  late HttpServer server;
  late Directory directory;
  late Future<void> Function(HttpRequest) beforeResponse;
  late List<String> requests;
  late List<bool> usedOriginalIdentity;
  late int responseStatus;
  var emptyEvents = false;

  MobileSession session(String account, {String suffix = 'old'}) =>
      MobileSession(
        accessToken: 'fixture-$suffix',
        deviceId: 'fixture-device',
        userId: account,
        displayName: account,
        username: account,
        policySignatureKey: '',
        imApiUrl: '',
        oaApiUrl: 'http://127.0.0.1:${server.port}',
      );

  Future<void> transition(String kind) => kind == 'logout'
      ? sessions.clearSession()
      : sessions.saveSession(
          session(kind == 'relogin' ? 'a' : 'b', suffix: 'new'),
        );

  Future<Map<String, Object?>> snapshot(String account) async => {
    for (final key in _keys) key: await store.readObject(account, key),
    OaLocalStore.notificationsCacheKey: await store.readList(
      account,
      OaLocalStore.notificationsCacheKey,
    ),
    'cursor': await store.lastEventSequence(account),
  };

  setUp(() async {
    HttpOverrides.global = _RealHttp();
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SecureSessionStore();
    directory = await Directory.systemTemp.createTemp('oa-event-session-');
    store = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => '${directory.path}/oa.db',
      const PlainImCacheCipher(),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    beforeResponse = (_) async {};
    requests = [];
    usedOriginalIdentity = [];
    responseStatus = 200;
    emptyEvents = false;
    server.listen((request) async {
      requests.add(request.uri.path);
      // Fixture credentials only; neither real tokens nor headers are logged.
      usedOriginalIdentity.add(
        request.headers.value('Authorization') == 'Bearer fixture-old' &&
            request.headers.value('X-Terminal-Account-Id') == 'a',
      );
      await beforeResponse(request);
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = responseStatus;
      final notification = {
        'id': 'notice-a',
        'title': 'server-a',
        'isRead': false,
      };
      final payload = switch (request.uri.path) {
        '/api/oa/sync/events' => {
          'events': emptyEvents
              ? []
              : [
                  for (var index = 0; index < 3; index++)
                    {
                      'id': 'event-$index',
                      'sequence': index + 1,
                      'type': [
                        'oa.request.updated',
                        'oa.app-catalog.changed',
                        'oa.attendance.changed',
                      ][index],
                      'payloadJson': jsonEncode({'requestId': 'approval-a'}),
                      'createdAt': '2026-09-02T00:00:00Z',
                    },
                ],
        },
        '/api/oa/notifications/page' => {
          'items': [notification],
          'hasMore': true,
          'nextCursor': 'next-a',
        },
        '/api/oa/bootstrap' => {
          'currentMember': {'id': 'a', 'displayName': 'server-a'},
          'notifications': [notification],
        },
        _ => {'marker': 'server-a', 'items': []},
      };
      request.response.write(jsonEncode(payload));
      await request.response.close();
    });
    repository = OaRepository(CollaborationClient(sessions), sessions, store);
    await sessions.saveSession(session('a'));
    for (final account in ['a', 'b']) {
      for (final key in _keys) {
        await store.writeObject(account, key, {
          'marker': 'before-$account',
          'items': [],
        });
      }
      await store.writeList(account, OaLocalStore.notificationsCacheKey, []);
    }
  });

  tearDown(() async {
    expect(usedOriginalIdentity.every((value) => value), true);
    await server.close(force: true);
    await store.close();
    await directory.delete(recursive: true);
    HttpOverrides.global = null;
  });

  for (final phase in _paths) {
    for (final change in ['account', 'relogin', 'logout']) {
      test(
        'OA sync rejects late $phase after $change without partial cache or cursor',
        () async {
          final old = await snapshot('a');
          final other = await snapshot('b');
          beforeResponse = (request) async {
            if (request.uri.path == phase) await transition(change);
          };
          await expectLater(
            repository.pullEvents(),
            throwsA(isA<SessionChangedException>()),
          );
          expect(requests, _paths.take(_paths.indexOf(phase) + 1).toList());
          expect(await snapshot('a'), old);
          expect(await snapshot('b'), other);
        },
      );
    }
  }

  for (final entry in ['catalog', 'attendance', 'notifications']) {
    for (final change in ['account', 'relogin', 'logout']) {
      test('OA $entry refresh rejects late response after $change', () async {
        final old = await snapshot('a');
        final other = await snapshot('b');
        beforeResponse = (_) => transition(change);
        final action = switch (entry) {
          'catalog' => repository.refreshAppCatalog(),
          'attendance' => repository.refreshAttendanceOverview(),
          _ => repository.refreshNotifications(),
        };
        await expectLater(action, throwsA(isA<SessionChangedException>()));
        expect(requests, hasLength(1));
        expect(await snapshot('a'), old);
        expect(await snapshot('b'), other);
      });
    }
  }

  for (final entry in [
    'catalog',
    'attendance',
    'notifications',
    'notification-page',
  ]) {
    test(
      'OA cache miss $entry cannot publish a response after relogin',
      () async {
        await store.invalidate('a', [
          ..._keys,
          OaLocalStore.notificationsCacheKey,
        ]);
        final old = await snapshot('a');
        beforeResponse = (_) => transition('relogin');
        final action = switch (entry) {
          'catalog' => repository.appCatalogCacheFirst(),
          'attendance' => repository.attendanceOverviewCacheFirst(),
          'notifications' => repository.notificationsCacheFirst(),
          _ => repository.notificationPageCacheFirst(),
        };
        await expectLater(action, throwsA(isA<SessionChangedException>()));
        expect(await snapshot('a'), old);
      },
    );
  }

  for (final phase in ['before-request', _paths.last]) {
    test('OA cancellation at $phase preserves cache and cursor', () async {
      final old = await snapshot('a');
      final cancel = CancelToken();
      if (phase == 'before-request') cancel.cancel('fixture-stop');
      beforeResponse = (request) async {
        if (request.uri.path == phase) cancel.cancel('fixture-stop');
      };
      await expectLater(
        repository.pullEvents(cancelToken: cancel),
        throwsA(
          isA<DioException>().having(
            (error) => CancelToken.isCancel(error),
            'cancelled',
            true,
          ),
        ),
      );
      expect(await snapshot('a'), old);
      expect(requests, phase == 'before-request' ? isEmpty : _paths);
    });
  }

  test('OA late HTTP failure is classified as stale session', () async {
    beforeResponse = (_) async {
      await transition('relogin');
      responseStatus = 500;
    };
    await expectLater(
      repository.pullEvents(),
      throwsA(isA<SessionChangedException>()),
    );
    expect(requests, [_paths.first]);
  });

  test('OA empty late event batch also rejects stale availability', () async {
    emptyEvents = true;
    beforeResponse = (_) => transition('relogin');
    await expectLater(
      repository.pullEvents(),
      throwsA(isA<SessionChangedException>()),
    );
    expect(requests, [_paths.first]);
  });

  for (final phase in _paths.skip(1)) {
    test('OA sync $phase HTTP 500 keeps the entire prior snapshot', () async {
      final old = await snapshot('a');
      beforeResponse = (request) async {
        if (request.uri.path == phase) responseStatus = 500;
      };
      await expectLater(repository.pullEvents(), throwsA(isA<DioException>()));
      expect(await snapshot('a'), old);
    });
  }

  test(
    'OA sync commits current session and preserves read receipts during replay',
    () async {
      final other = await snapshot('b');
      await store.enqueueNotificationRead('a', 'notice-a');
      final first = await repository.pullEvents();
      expect(first.changed, true);
      expect(first.sequence, 3);
      expect(first.requestIds, {'approval-a'});
      expect(await store.lastEventSequence('a'), 3);
      final page = await repository.notificationPageCacheFirst();
      expect(page.items.single.isRead, true);
      expect(page.nextCursor, 'next-a');
      expect(page.hasMore, true);
      expect(
        (await repository.bootstrapCacheFirst()).notifications.single.isRead,
        true,
      );
      expect((await repository.notificationsCacheFirst()).single.isRead, true);
      final saved = await snapshot('a');
      final repeated = await repository.pullEvents();
      expect(repeated.changed, false);
      expect(repeated.sequence, 3);
      expect(await snapshot('a'), saved);
      expect(await snapshot('b'), other);
      expect(requests, [..._paths, _paths.first]);
    },
  );
}

class _RealHttp extends HttpOverrides {}

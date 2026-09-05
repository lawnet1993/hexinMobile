import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/oa_catalog_sync_coordinator.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 1));
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    condition(),
    true,
    reason: 'Expected recovery without waiting for the long poll or 3s backoff',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late _Fixture f;
  setUp(() async {
    HttpOverrides.global = _RealHttp();
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.close();
    HttpOverrides.global = null;
  });

  test(
    'OA radio recovery refreshes SQLite before returning to long polling',
    () async {
      await f.coordinator.start();
      await _until(() => f.longPolls == 1);
      f.version = 'recovered';
      f.network.add([ConnectivityResult.none]);
      f.network.add([ConnectivityResult.wifi]);
      // Request receipt is not completion: observe the callback emitted only
      // after all workspace projections have been persisted.
      await _until(() => f.changed >= 2);
      expect(
        (await f.store.readObject(
          'account',
          OaLocalStore.catalogCacheKey,
        ))!['catalogVersion'],
        'recovered',
      );
      await _until(() => f.longPolls >= 2);
      expect(f.waits, [0, 20, 0, 20]);
      final reads = f.bootstrapReads;
      for (var i = 0; i < 5; i++) {
        f.network.add([ConnectivityResult.wifi]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.bootstrapReads, reads);
      expect(f.releasePolls.isCompleted, false);
    },
  );

  test(
    'OA foreground wake refreshes once while repeated wakeups coalesce',
    () async {
      await f.coordinator.start();
      await _until(() => f.longPolls == 1);
      final hold = Completer<void>();
      f.workspaceBarrier = hold;
      f.coordinator.synchronizeNow();
      await _until(() => f.bootstrapReads == 2);
      for (var i = 0; i < 5; i++) {
        f.coordinator.synchronizeNow();
      }
      hold.complete();
      await _until(() => f.longPolls == 2);
      expect(f.bootstrapReads, 2);
    },
  );

  test('OA network recovery interrupts failure backoff without optimistic availability', () async {
    f.status = 503;
    await f.coordinator.start();
    await _until(() => f.unavailable > 0);
    expect(f.available, 0);
    f.status = 200;
    f.network.add([ConnectivityResult.none]);
    f.network.add([ConnectivityResult.mobile]);
    await _until(() => f.available > 0);
    expect(
      (await f.store.readObject(
        'account',
        OaLocalStore.catalogCacheKey,
      ))!['catalogVersion'],
      'one',
    );
  });

  test(
    'OA stop during startup cancels reads and suppresses late callbacks',
    () async {
      final hold = Completer<void>();
      f.workspaceBarrier = hold;
      final starting = f.coordinator.start();
      await _until(() => f.bootstrapReads == 1);
      await f.coordinator.stop().timeout(const Duration(seconds: 1));
      hold.complete();
      await starting.timeout(const Duration(seconds: 1));
      expect(f.available, 0);
      expect(f.changed, 0);
      expect(f.waits, isEmpty);
      expect(
        await f.store.readObject('account', OaLocalStore.catalogCacheKey),
        isNull,
      );
      expect(f.network.hasListener, false);
    },
  );

  test(
    'OA stopped coordinator ignores network and foreground wakeups',
    () async {
      await f.coordinator.start();
      await _until(() => f.longPolls == 1);
      await f.coordinator.stop();
      final connecting = f.connecting;
      final reads = f.bootstrapReads;
      f.network.add([ConnectivityResult.wifi]);
      f.coordinator.synchronizeNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.connecting, connecting);
      expect(f.bootstrapReads, reads);
      expect(f.network.hasListener, false);
    },
  );

  test(
    'OA rapid restart owns its loop after the old startup is cancelled',
    () async {
      final hold = Completer<void>();
      f.workspaceBarrier = hold;
      final oldStart = f.coordinator.start();
      await _until(() => f.bootstrapReads == 1);
      final stopping = f.coordinator.stop();
      f.workspaceBarrier = null;
      final newStart = f.coordinator.start();
      await Future.wait([oldStart, stopping, newStart])
          .timeout(const Duration(seconds: 1));
      await _until(() => f.longPolls == 1);
      expect(f.changed, 1);
      expect(f.network.hasListener, true);
      hold.complete();
      f.coordinator.synchronizeNow();
      await _until(() => f.longPolls == 2);
      expect(f.changed, 2);
      expect(f.bootstrapReads, 3);
      expect(f.waits, [0, 20, 0, 20]);
    },
  );

  test(
    'OA stop interrupts failure backoff and makes no late requests',
    () async {
      f.status = 503;
      await f.coordinator.start();
      await _until(() => f.unavailable > 0);
      await f.coordinator.stop().timeout(const Duration(seconds: 1));
      final reads = f.bootstrapReads;
      f.network.add([ConnectivityResult.wifi]);
      f.coordinator.synchronizeNow();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(f.bootstrapReads, reads);
      expect(f.available, 0);
      expect(f.network.hasListener, false);
    },
  );

  test(
    'OA an available radio does not turn a 503 into service recovery',
    () async {
      f.status = 503;
      await f.coordinator.start();
      await _until(() => f.unavailable > 0);
      f.network.add([ConnectivityResult.wifi]);
      await _until(() => f.bootstrapReads == 2 && f.unavailable >= 2);
      for (var i = 0; i < 5; i++) {
        f.network.add([ConnectivityResult.wifi]);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(f.available, 0);
      expect(f.bootstrapReads, 2);
      expect(f.waits, isEmpty);
    },
  );

  test(
    'OA queued event pages catch up immediately and persist the cursor',
    () async {
      f.eventCount = 201;
      await f.coordinator.start();
      await _until(() => f.longPolls == 1);
      expect(f.waits, [0, 0, 0, 20]);
      expect(f.cursors, [0, 200, 201, 201]);
      expect(await f.store.lastEventSequence('account'), 201);
      expect(f.changed, 3);
    },
  );

  test('OA local mutation interrupts only the held poll and commits real events', () async {
    await f.coordinator.start();
    await _until(() => f.longPolls == 1);
    f.eventCount = 1;
    f.coordinator.catchUpAfterMutation();
    await _until(() => f.longPolls == 2);
    expect(f.releasePolls.isCompleted, false);
    expect(f.waits, [0, 20, 0, 0, 20]);
    expect(await f.store.lastEventSequence('account'), 1);
    expect(f.changed, 2);
    expect(f.bootstrapReads, 2, reason: 'Only initial workspace and event projection');
    expect(f.connecting, 1, reason: 'No connecting banner for a local write');
    expect(f.unavailable, 0);
  });

  test('OA mutation hints coalesce without cancelling a zero-wait catch-up', () async {
    await f.coordinator.start();
    await _until(() => f.longPolls == 1);
    final hold = Completer<void>();
    f.immediateBarrier = hold;
    f.coordinator.catchUpAfterMutation();
    await _until(() => f.waits.length == 3);
    for (var index = 0; index < 10; index++) {
      f.coordinator.catchUpAfterMutation();
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(f.waits, [0, 20, 0]);
    f.eventCount = 1;
    hold.complete();
    await _until(() => f.longPolls == 2);
    expect(f.waits, [0, 20, 0, 0, 20]);
    expect(f.changed, 2);
    expect(await f.store.lastEventSequence('account'), 1);
  });

  test('OA mutation during workspace startup does not abort projection writes', () async {
    final hold = Completer<void>();
    f.workspaceBarrier = hold;
    final starting = f.coordinator.start();
    await _until(() => f.bootstrapReads == 1);
    f.coordinator.catchUpAfterMutation();
    hold.complete();
    await starting;
    await _until(() => f.longPolls == 1);
    expect(f.bootstrapReads, 1);
    expect(f.changed, 1);
    expect(f.waits, [0, 20]);
    expect(f.unavailable, 0);
  });

  test('OA stopped mutation hints cannot restart synchronization', () async {
    await f.coordinator.start();
    await _until(() => f.longPolls == 1);
    await f.coordinator.stop();
    f.coordinator.catchUpAfterMutation();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(f.waits, [0, 20]);
    expect(f.changed, 1);
  });

  test('OA mutation hint without server event never fabricates a cursor', () async {
    await f.coordinator.start();
    await _until(() => f.longPolls == 1);
    f.coordinator.catchUpAfterMutation();
    await _until(() => f.longPolls == 2);
    expect(f.waits, [0, 20, 0, 20]);
    expect(await f.store.lastEventSequence('account'), 0);
    expect(f.changed, 1);
  });

  for (final succeeds in [true, false]) {
    test('OA notification UI wakes event sync only after successful delivery: $succeeds', () async {
      final container = ProviderContainer(overrides: [
        oaRepositoryProvider.overrideWithValue(f.repository),
        oaCatalogSyncCoordinatorProvider.overrideWithValue(f.coordinator),
      ]);
      addTearDown(container.dispose);
      await f.coordinator.start();
      await _until(() => f.longPolls == 1);
      f.status = succeeds ? 200 : 503;
      await container.read(notificationReadSynchronizerProvider)(
        OaNotification.fromJson({'id': 'notice-fixture', 'targetKind': 'oa_approval'}),
      );
      await _until(() => f.notificationPosts == 1);
      if (succeeds) {
        await _until(() => f.longPolls == 2);
        expect(await f.store.lastEventSequence('account'), 1);
        expect(await f.repository.pendingNotificationReadCount(), 0);
        expect(f.changed, 2);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(f.waits, [0, 20]);
        expect(await f.store.lastEventSequence('account'), 0);
        expect(await f.repository.pendingNotificationReadCount(), 1);
        expect(f.changed, 1);
      }
    });
  }
}

class _Fixture {
  _Fixture(this.server, this.sessions, this.store);
  final HttpServer server;
  final SecureSessionStore sessions;
  final OaLocalStore store;
  final network = StreamController<List<ConnectivityResult>>.broadcast(
    sync: true,
  );
  final releasePolls = Completer<void>();
  Completer<void>? workspaceBarrier;
  Completer<void>? immediateBarrier;
  late final OaSyncCoordinator coordinator;
  late final OaRepository repository;
  String version = 'one';
  int status = 200;
  int bootstrapReads = 0;
  int longPolls = 0;
  int available = 0;
  int unavailable = 0;
  int connecting = 0;
  int changed = 0;
  int eventCount = 0;
  int notificationPosts = 0;
  final waits = <int>[];
  final cursors = <int>[];

  static Future<_Fixture> create() async {
    FlutterSecureStorage.setMockInitialValues({});
    final sessions = SecureSessionStore();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final store = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => inMemoryDatabasePath,
      const PlainImCacheCipher(),
    );
    final f = _Fixture(server, sessions, store);
    await sessions.saveSession(
      MobileSession(
        accessToken: 'local-fixture',
        deviceId: 'fixture-device',
        userId: 'account',
        displayName: 'Test',
        username: 'test',
        policySignatureKey: '',
        imApiUrl: '',
        oaApiUrl: 'http://127.0.0.1:${server.port}',
      ),
    );
    server.listen(f.handle);
    f.repository = OaRepository(CollaborationClient(sessions), sessions, store);
    f.coordinator = OaSyncCoordinator(
      f.repository,
      connectivityChanges: f.network.stream,
      onChanged: () => f.changed++,
      onConnecting: () => f.connecting++,
      onAvailable: () => f.available++,
      onUnavailable: () => f.unavailable++,
      onRequestsChanged: (_) {},
    );
    return f;
  }

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'POST' && path == '/api/oa/notifications/notice-fixture/read') {
      notificationPosts++;
      if (status == 200) eventCount++;
    }
    if (path == '/api/oa/bootstrap') bootstrapReads++;
    if (path == '/api/oa/sync/events') {
      final wait = int.parse(request.uri.queryParameters['waitSeconds']!);
      waits.add(wait);
      cursors.add(int.parse(request.uri.queryParameters['afterSequence']!));
      if (wait > 0) {
        longPolls++;
        await releasePolls.future;
      } else {
        await immediateBarrier?.future;
      }
    } else {
      await workspaceBarrier?.future;
    }
    try {
      request.response.statusCode = path == '/api/oa/sync/events'
          ? 200
          : status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(switch (path) {
          '/api/oa/bootstrap' => {
            'currentMember': {'id': 'account', 'displayName': 'Test'},
          },
          '/api/oa/app-catalog' => {'catalogVersion': version, 'items': []},
          '/api/oa/notifications/page' => {'items': [], 'hasMore': false},
          '/api/oa/sync/events' => {
            'events': [
              for (
                var sequence =
                    int.parse(request.uri.queryParameters['afterSequence']!) +
                    1;
                sequence <= eventCount &&
                    sequence <=
                        int.parse(
                              request.uri.queryParameters['afterSequence']!,
                            ) +
                            200;
                sequence++
              )
                {
                  'id': 'event-$sequence',
                  'sequence': sequence,
                  'type': 'oa.notification.read',
                  'payload': <String, Object?>{},
                },
            ],
          },
          _ => <String, Object?>{},
        }),
      );
      await request.response.close();
    } on HttpException {
      // Expected for a request intentionally cancelled by the coordinator.
    } on SocketException {
      // Expected for a request intentionally cancelled by the coordinator.
    }
  }

  Future<void> close() async {
    if (!releasePolls.isCompleted) releasePolls.complete();
    if (workspaceBarrier != null && !workspaceBarrier!.isCompleted) {
      workspaceBarrier!.complete();
    }
    if (immediateBarrier != null && !immediateBarrier!.isCompleted) {
      immediateBarrier!.complete();
    }
    await coordinator.stop();
    await network.close();
    await server.close(force: true);
    await store.close();
  }
}

class _RealHttp extends HttpOverrides {}

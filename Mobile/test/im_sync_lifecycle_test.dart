import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/im_sync_coordinator.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'disposing an unstarted real provider never writes disposed state',
    () async {
      final f = await _Fixture.create();
      final container = ProviderContainer(
        overrides: [imRepositoryProvider.overrideWithValue(f.repository)],
      );
      container.read(imSyncCoordinatorProvider);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(f.bootstrapCalls, 0);
    },
  );

  for (final fail in [false, true]) {
    test(
      'stopped bootstrap ignores late ${fail ? 'failure' : 'success'}',
      () async {
        final f = await _Fixture.create(
          holdBootstrap: true,
          failBootstrap: fail,
        );
        final start = f.coordinator.start();
        await f.bootstrapEntered.future.timeout(const Duration(seconds: 3));
        await f.coordinator.stop();
        f.releaseBootstrap.complete();
        await start;
        expect(f.changes, 0);
        expect(f.availability, ImRealtimeAvailability.unavailable);
        expect(f.pullCalls, 0);
      },
    );
  }

  test(
    'restart cannot revive the old bootstrap or create a second loop',
    () async {
      final f = await _Fixture.create(holdBootstrap: true);
      final oldStart = f.coordinator.start();
      await f.bootstrapEntered.future.timeout(const Duration(seconds: 3));
      await f.coordinator.stop();
      await f.coordinator.start();
      await f.pullEntered.future.timeout(const Duration(seconds: 3));
      f.releaseBootstrap.complete();
      await oldStart;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(f.bootstrapCalls, 2);
      expect(
        f.changes,
        1,
        reason: 'Only the new generation may publish bootstrap',
      );
      expect(
        f.pullCalls,
        1,
        reason: 'Only one long-poll loop may remain active',
      );
    },
  );

  test('stop cancels held long poll and resolves push wake waiters', () async {
    final f = await _Fixture.create();
    await f.coordinator.start();
    await f.pullEntered.future.timeout(const Duration(seconds: 3));
    final waiter = f.coordinator.synchronizeNowAndWait();
    await f.coordinator.stop().timeout(const Duration(seconds: 3));
    await waiter.timeout(const Duration(seconds: 1));
    expect(f.availability, ImRealtimeAvailability.unavailable);
    final calls = f.pullCalls;
    f.coordinator.synchronizeNow(reconcileConversations: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(f.pullCalls, calls);
  });

  for (final fail in [false, true]) {
    test(
      'disposed coordinator ignores pending bootstrap ${fail ? 'failure' : 'success'}',
      () async {
        final f = await _Fixture.create(
          holdBootstrap: true,
          failBootstrap: fail,
        );
        final started = f.coordinator.start();
        await f.bootstrapEntered.future.timeout(const Duration(seconds: 3));
        f.coordinator.dispose();
        f.container.dispose();
        f.containerDisposed = true;
        f.releaseBootstrap.complete();
        await started;
        await f.coordinator.start();
        expect(f.bootstrapCalls, 1, reason: 'Disposed objects cannot restart');
        expect(f.changes, 0);
        expect(f.pullCalls, 0);
      },
    );
  }

  test('late session termination cannot stop a restarted sync loop', () async {
    final invalidEntered = Completer<void>();
    final invalidResult = Completer<bool>();
    final f = await _Fixture.create(
      rejectFirstPull: true,
      onSessionInvalid: () {
        invalidEntered.complete();
        return invalidResult.future;
      },
    );
    await f.coordinator.start();
    await invalidEntered.future.timeout(const Duration(seconds: 3));
    final stopped = f.coordinator.stop();
    await f.coordinator.start();
    final newWaiter = f.coordinator.synchronizeNowAndWait();
    invalidResult.complete(true);
    await stopped;
    expect(f.availability, ImRealtimeAvailability.available);
    await f.coordinator.stop();
    await newWaiter.timeout(const Duration(seconds: 1));
  });

  test(
    'slow connectivity cancellation cannot overwrite new runtime handles',
    () async {
      final stream = _DelayedCancelStream();
      final f = await _Fixture.create(connectivityChanges: stream);
      await f.coordinator.start();
      await f.pullEntered.future.timeout(const Duration(seconds: 3));
      final stopped = f.coordinator.stop();
      await stream.cancelEntered.future.timeout(const Duration(seconds: 1));
      await f.coordinator.start();
      stream.cancelDone.complete();
      await stopped;
      expect(f.availability, ImRealtimeAvailability.available);
      await f.coordinator.stop();
      expect(stream.listenCount, 2);
    },
  );
}

class _Fixture {
  _Fixture(this.server, this.sessions, this.store, this.container)
    : repository = ImRepository(CollaborationClient(sessions), sessions, store);

  final HttpServer server;
  final SecureSessionStore sessions;
  final ImLocalStore store;
  final ProviderContainer container;
  final ImRepository repository;
  late final ImSyncCoordinator coordinator;
  final bootstrapEntered = Completer<void>();
  final releaseBootstrap = Completer<void>();
  final pullEntered = Completer<void>();
  final releasePull = Completer<void>();
  int changes = 0;
  int bootstrapCalls = 0;
  int pullCalls = 0;
  bool containerDisposed = false;

  ImRealtimeAvailability get availability =>
      container.read(imRealtimeAvailabilityProvider);

  static Future<_Fixture> create({
    bool holdBootstrap = false,
    bool failBootstrap = false,
    bool rejectFirstPull = false,
    Future<bool> Function()? onSessionInvalid,
    Stream<List<ConnectivityResult>>? connectivityChanges,
  }) async {
    HttpOverrides.global = _RealHttpOverrides();
    FlutterSecureStorage.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sessions = SecureSessionStore();
    await sessions.saveSession(
      MobileSession(
        accessToken: 'local-lifecycle-fixture',
        deviceId: 'fixture-device',
        userId: 'account',
        displayName: 'Fixture',
        username: 'fixture',
        policySignatureKey: '',
        imApiUrl: 'http://127.0.0.1:${server.port}',
        oaApiUrl: '',
      ),
    );
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    final f = _Fixture(server, sessions, store, ProviderContainer());
    f.coordinator = ImSyncCoordinator(
      f.repository,
      availabilityController: f.container.read(
        imRealtimeAvailabilityControllerProvider.notifier,
      ),
      onChanged: (_) => f.changes++,
      connectivityChanges: connectivityChanges,
      onSessionInvalid: (_) => onSessionInvalid?.call() ?? Future.value(false),
    );
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      Object payload = {};
      if (request.uri.path == '/api/im/bootstrap') {
        f.bootstrapCalls++;
        if (!f.bootstrapEntered.isCompleted) f.bootstrapEntered.complete();
        if (holdBootstrap && f.bootstrapCalls == 1) {
          await f.releaseBootstrap.future;
        }
        if (failBootstrap) request.response.statusCode = 503;
        payload = {
          'currentMember': {'id': 'account', 'username': 'fixture'},
          'contacts': [],
          'conversations': [],
        };
      } else if (request.uri.path == '/api/im/sync/events') {
        f.pullCalls++;
        if (!f.pullEntered.isCompleted) f.pullEntered.complete();
        if (rejectFirstPull && f.pullCalls == 1) {
          request.response.statusCode = 401;
        } else {
          await f.releasePull.future;
        }
        payload = {'events': [], 'latestSequence': 0};
      } else if (request.uri.path == '/api/im/conversations') {
        payload = [];
      }
      try {
        request.response.write(jsonEncode(payload));
        await request.response.close();
      } catch (_) {
        // Held requests may have been cancelled by stop().
      }
    });
    addTearDown(() async {
      final stopped = f.coordinator.stop();
      if (!f.releaseBootstrap.isCompleted) f.releaseBootstrap.complete();
      if (!f.releasePull.isCompleted) f.releasePull.complete();
      await stopped;
      await server.close(force: true);
      if (!f.containerDisposed) f.container.dispose();
      await store.close();
      HttpOverrides.global = null;
      FlutterSecureStorage.setMockInitialValues({});
    });
    return f;
  }
}

class _RealHttpOverrides extends HttpOverrides {}

class _DelayedCancelStream extends Stream<List<ConnectivityResult>> {
  final cancelEntered = Completer<void>();
  final cancelDone = Completer<void>();
  int listenCount = 0;

  @override
  StreamSubscription<List<ConnectivityResult>> listen(
    void Function(List<ConnectivityResult>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final first = ++listenCount == 1;
    final controller = StreamController<List<ConnectivityResult>>(
      onCancel: () async {
        if (first) {
          cancelEntered.complete();
          await cancelDone.future;
        }
      },
    );
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

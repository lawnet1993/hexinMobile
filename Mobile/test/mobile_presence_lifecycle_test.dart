import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/api_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/mobile_presence_coordinator.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restart during session maintenance checks immediately and owns one timer',
    () async {
      final f = await _Fixture.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      f.auth.beforeMaintain = (call) async {
        if (call == 1) {
          entered.complete();
          await release.future;
        }
      };
      final oldStart = f.start();
      await entered.future;
      f.presence.stop();
      final restarted = f.start();
      await _settle();
      final immediateChecks = f.auth.maintainCalls;
      release.complete();
      await Future.wait([oldStart, restarted]);
      expect(
        immediateChecks,
        2,
        reason: 'Old maintenance cannot suppress the new start',
      );
      expect(f.calls, 1);
      expect(f.activeTimers, 1, reason: 'Old start cannot arm a second timer');
      f.presence.stop();
      expect(f.activeTimers, 0);
    },
  );

  test('concurrent resume callers await the same heartbeat', () async {
    final f = await _Fixture.create(holdFirst: true);
    final first = f.presence.synchronizeNow();
    await f.firstEntered.future;
    var secondDone = false;
    final second = f.presence.synchronizeNow().then((_) => secondDone = true);
    await _settle();
    final completedEarly = secondDone;
    f.releaseFirst.complete();
    await Future.wait([first, second]);
    expect(completedEarly, false);
    expect(f.calls, 1);
  });

  test(
    'stop cancels held HTTP and restarted heartbeat does not wait for it',
    () async {
      final f = await _Fixture.create(holdFirst: true);
      final oldStart = f.start();
      await f.firstEntered.future;
      f.presence.stop();
      var oldDone = false;
      final stopped = oldStart.then((_) => oldDone = true);
      await f.start();
      await _settle();
      final stoppedPromptly = oldDone;
      final callsBeforeRelease = f.calls;
      f.releaseFirst.complete();
      await stopped;
      expect(
        stoppedPromptly,
        true,
        reason: 'Stop must cancel the in-flight heartbeat',
      );
      expect(callsBeforeRelease, 2);
      expect(f.activeTimers, 1);
    },
  );

  test('old completion cannot unlock a new held heartbeat', () async {
    final f = await _Fixture.create();
    final entered = Completer<void>();
    final oldRelease = Completer<void>();
    final newEntered = Completer<void>();
    final newRelease = Completer<void>();
    f.auth.beforeMaintain = (call) async {
      if (call == 1) {
        entered.complete();
        await oldRelease.future;
      } else if (call == 2) {
        newEntered.complete();
        await newRelease.future;
      }
    };
    final first = f.start();
    await entered.future;
    f.presence.stop();
    final second = f.start();
    await _settle();
    // Release every fixture even when the expected new operation was skipped.
    oldRelease.complete();
    await first;
    final third = f.presence.synchronizeNow();
    await _settle();
    final callsWhileHeld = f.auth.maintainCalls;
    newRelease.complete();
    await Future.wait([second, third]);
    expect(newEntered.isCompleted, true);
    expect(callsWhileHeld, 2);
    expect(f.calls, 1);
    expect(f.activeTimers, 1);
  });

  test('late termination result cannot stop a restarted loop', () async {
    final f = await _Fixture.create(firstStatus: 401);
    final entered = Completer<void>();
    final result = Completer<bool>();
    f.auth.onFailure = (_) {
      entered.complete();
      return result.future;
    };
    final oldStart = f.start();
    await entered.future;
    f.presence.stop();
    final restarted = f.start();
    await _settle();
    result.complete(true);
    await Future.wait([oldStart, restarted]);
    expect(f.activeTimers, 1);
    final calls = f.calls;
    f.tick();
    await _settle();
    expect(f.calls, calls + 1);
  });

  test(
    'disposed provider cannot be restarted through a retained reference',
    () async {
      final f = await _Fixture.create();
      f.container.dispose();
      f.disposed = true;
      await f.start();
      await f.presence.synchronizeNow();
      expect(f.activeTimers, 0);
      expect(f.auth.maintainCalls, 0);
      expect(f.calls, 0);
    },
  );

  test(
    'stop during initial maintenance leaves no timer or heartbeat',
    () async {
      final f = await _Fixture.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      f.auth.beforeMaintain = (_) async {
        entered.complete();
        await release.future;
      };
      final started = f.start();
      await entered.future;
      f.presence.stop();
      release.complete();
      await started;
      expect(f.activeTimers, 0);
      expect(f.calls, 0);
    },
  );

  test(
    'steady timer checks once every tick and cannot run after stop',
    () async {
      final f = await _Fixture.create();
      await f.start();
      await f.start();
      expect(f.calls, 1);
      expect(f.timers.single.duration, const Duration(seconds: 30));
      f.tick();
      await _settle();
      expect(f.calls, 2);
      f.presence.stop();
      f.tick();
      await _settle();
      expect(f.calls, 2);
    },
  );

  test(
    'heartbeat carries independent install id and cross-domain sync health',
    () async {
      final f = await _Fixture.create();
      await f.start();

      final heartbeat = f.heartbeats.single;
      expect(heartbeat['deviceId'], 'fixture-device');
      expect(heartbeat['installationId'], isNotEmpty);
      expect(heartbeat['installationId'], isNot(heartbeat['deviceId']));
      expect(heartbeat['imSync'], containsPair('mode', 'http_long_poll'));
      expect(heartbeat['imSync'], containsPair('cursorHealth', 'unavailable'));
      expect(heartbeat['oaSync'], containsPair('mode', 'http_long_poll'));
      expect(heartbeat['oaSync'], containsPair('state', 'unavailable'));
    },
  );

  for (final status in [409, 500, 503]) {
    test(
      'temporary HTTP $status keeps login and recovers on the next heartbeat',
      () async {
        final f = await _Fixture.create(firstStatus: status);
        await f.start();
        expect(f.auth.failureCalls, 0);
        expect(await f.store.readSession(), isNotNull);
        expect(f.container.read(sessionTerminationNoticeProvider), isNull);
        f.tick();
        await _settle();
        expect(f.calls, 2);
        expect(f.activeTimers, 1);
      },
    );
  }

  for (final status in [401, 409]) {
    test(
      'authoritative HTTP $status stops the current loop and emits one notice',
      () async {
        final f = await _Fixture.create(
          firstStatus: status,
          replaced: status == 409,
        );
        await f.start();
        expect(await f.store.readSession(), isNull);
        expect(f.container.read(sessionTerminationNoticeProvider), isNotNull);
        expect(f.activeTimers, 0);
        f.tick();
        await _settle();
        expect(f.calls, 1);
        expect(f.auth.failureCalls, 1);
      },
    );
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 70));

class _Auth extends AuthController {
  _Auth(this.store);
  final SecureSessionStore store;
  int maintainCalls = 0;
  int failureCalls = 0;
  Future<void> Function(int)? beforeMaintain;
  Future<bool> Function(DioException)? onFailure;

  @override
  Future<MobileSession?> maintainSession() async {
    await beforeMaintain?.call(++maintainCalls);
    return store.readSession();
  }

  @override
  Future<bool> handleSessionFailure(DioException error) {
    failureCalls++;
    return onFailure?.call(error) ?? super.handleSessionFailure(error);
  }
}

class _Fixture {
  _Fixture(this.server, this.store, this.auth, this.api, this.container);
  final HttpServer server;
  final SecureSessionStore store;
  final _Auth auth;
  final Dio api;
  final ProviderContainer container;
  late MobilePresenceCoordinator presence;
  final firstEntered = Completer<void>();
  final releaseFirst = Completer<void>();
  final timers = <_ManualTimer>[];
  final heartbeats = <Map<String, Object?>>[];
  int calls = 0;
  bool disposed = false;
  int get activeTimers => timers.where((timer) => timer.isActive).length;

  Future<void> start() => runZoned(
    presence.start,
    zoneSpecification: ZoneSpecification(
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        final timer = _ManualTimer(
          duration,
          (timer) => zone.runGuarded(() => callback(timer)),
        );
        timers.add(timer);
        return timer;
      },
    ),
  );

  void tick() {
    for (final timer in timers.toList()) {
      timer.fire();
    }
  }

  static Future<_Fixture> create({
    bool holdFirst = false,
    int firstStatus = 204,
    bool replaced = false,
  }) async {
    HttpOverrides.global = _RealHttpOverrides();
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final store = SecureSessionStore();
    await store.saveSession(
      const MobileSession(
        accessToken: 'fixture-session',
        deviceId: 'fixture-device',
        userId: 'fixture-user',
        displayName: 'Fixture',
        username: 'fixture',
        policySignatureKey: '',
        imApiUrl: '',
        oaApiUrl: '',
      ),
    );
    final auth = _Auth(store);
    final api = Dio(
      BaseOptions(
        baseUrl: 'http://127.0.0.1:${server.port}',
        receiveTimeout: const Duration(seconds: 3),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        secureSessionStoreProvider.overrideWithValue(store),
        authControllerProvider.overrideWith(() => auth),
        dioProvider.overrideWithValue(api),
        mobileImSyncHealthLoaderProvider.overrideWithValue(
          (_) async => const MobileImSyncHealth.unavailable(),
        ),
        mobileOaSyncHealthLoaderProvider.overrideWithValue(
          (_) async => const MobileOaSyncHealth.unavailable(),
        ),
      ],
    );
    final f = _Fixture(server, store, auth, api, container);
    server.listen((request) async {
      final rawBody = await utf8.decoder.bind(request).join();
      if (request.uri.path != '/api/client/heartbeat') {
        request.response.statusCode = 204;
        await request.response.close();
        return;
      }
      if (rawBody.isNotEmpty) {
        f.heartbeats.add((jsonDecode(rawBody) as Map).cast<String, Object?>());
      }
      final call = ++f.calls;
      if (call == 1) {
        f.firstEntered.complete();
        if (holdFirst) await f.releaseFirst.future;
      }
      request.response.statusCode = call == 1 ? firstStatus : 204;
      if (call == 1 && firstStatus != 204) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(replaced ? '{"code":"session_replaced"}' : '{}');
      }
      await request.response.close();
    });
    await container.read(authControllerProvider.future);
    f.presence = container.read(mobilePresenceCoordinatorProvider);
    addTearDown(() async {
      if (!f.releaseFirst.isCompleted) f.releaseFirst.complete();
      f.presence.stop();
      if (!f.disposed) container.dispose();
      for (final timer in f.timers) {
        timer.cancel();
      }
      api.close(force: true);
      await server.close(force: true);
    });
    return f;
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this.callback);
  final Duration duration;
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    if (isActive) {
      tick++;
      callback(this);
    }
  }

  @override
  void cancel() => isActive = false;
}

class _RealHttpOverrides extends HttpOverrides {}

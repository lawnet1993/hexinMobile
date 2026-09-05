import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hexing_terminal_mobile/core/notifications/mobile_push_registration.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';

const _token = MobilePushToken(
  platform: 'android',
  provider: 'fcm',
  value: 'fixture-token',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  MobileSession session(String account, String token) => MobileSession(
    accessToken: token,
    deviceId: 'fixture-device',
    userId: account,
    username: account,
    displayName: account,
    policySignatureKey: '',
    imApiUrl: 'http://127.0.0.1',
    oaApiUrl: '',
  );

  for (final transition in ['logout', 'account', 'refresh']) {
    test(
      '$transition during token lookup cannot register using the new session',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final store = SecureSessionStore();
        await store.saveSession(session('a', 'fixture-old'));
        final source = _Source()..lookup = Completer<MobilePushToken?>();
        var registered = 0;
        final registration = MobilePushRegistration(
          source,
          sessionStore: store,
          register:
              ({
                required platform,
                required provider,
                required token,
                privacyMode = 'summary',
                forSession,
              }) async {
                registered++;
              },
          unregister: ({forSession}) async {},
        );
        final syncing = registration.synchronize();
        await settle();
        if (transition == 'logout') {
          await store.clearSession();
        } else {
          await store.saveSession(
            session(transition == 'account' ? 'b' : 'a', 'fixture-new'),
          );
        }
        source.lookup!.complete(_token);
        expect(await syncing, isFalse);
        expect(registered, 0);
        registration.stop();
        await source.close();
      },
    );
  }

  test(
    'session refresh re-registers same push token with captured credentials',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      await store.saveSession(session('a', 'fixture-old'));
      final source = _Source();
      final bound = <MobileSession?>[];
      final registration = MobilePushRegistration(
        source,
        sessionStore: store,
        register:
            ({
              required platform,
              required provider,
              required token,
              privacyMode = 'summary',
              forSession,
            }) async {
              bound.add(forSession);
            },
        unregister: ({forSession}) async {},
      );
      await registration.synchronize();
      await store.saveSession(session('a', 'fixture-new'));
      await registration.synchronize();
      expect(bound.map((item) => item?.accessToken), [
        'fixture-old',
        'fixture-new',
      ]);
      registration.stop();
      await source.close();
    },
  );

  for (final action in ['register', 'unregister']) {
    test(
      'late $action cannot overwrite or clear new account secure token',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final store = SecureSessionStore();
        await store.saveSession(session('a', 'fixture-old'));
        final source = _Source();
        final entered = Completer<void>();
        final pending = Completer<void>();
        MobileSession? captured;
        final registration = MobilePushRegistration(
          source,
          sessionStore: store,
          register:
              ({
                required platform,
                required provider,
                required token,
                privacyMode = 'summary',
                forSession,
              }) async {
                captured = forSession;
                if (action == 'register') {
                  entered.complete();
                  await pending.future;
                }
              },
          unregister: ({forSession}) async {
            captured = forSession;
            entered.complete();
            await pending.future;
          },
          saveSecureToken: store.savePushToken,
          clearSecureToken: store.clearPushToken,
        );
        final operation = action == 'register'
            ? registration.synchronize()
            : registration.unregister();
        await entered.future;
        await store.saveSession(session('b', 'fixture-new'));
        await store.savePushToken('fixture-new-account-token');
        pending.complete();
        await operation;
        expect(captured?.userId, 'a');
        expect(await store.readPushToken(), 'fixture-new-account-token');
        registration.stop();
        await source.close();
      },
    );
  }

  test(
    'stop during token lookup prevents registration and initial navigation',
    () async {
      final source = _Source()..lookup = Completer<MobilePushToken?>();
      var registered = 0;
      final routes = <String>[];
      final registration = MobilePushRegistration(
        source,
        register:
            ({
              required platform,
              required provider,
              required token,
              privacyMode = 'summary',
              forSession,
            }) async {
              registered++;
            },
        unregister: ({forSession}) async {},
      );
      final starting = registration.start(onOpenRoute: routes.add);
      await settle();
      registration.stop();
      source.lookup!.complete(_token);
      await starting;
      expect(registered, 0);
      expect(routes, isEmpty);
      await source.close();
    },
  );

  test('late registration success cannot save a token after stop', () async {
    final source = _Source();
    final pending = Completer<void>();
    final entered = Completer<void>();
    final saved = <String>[];
    final registration = MobilePushRegistration(
      source,
      register:
          ({
            required platform,
            required provider,
            required token,
            privacyMode = 'summary',
            forSession,
          }) async {
            entered.complete();
            await pending.future;
          },
      unregister: ({forSession}) async {},
      saveSecureToken: (value) async {
        saved.add(value);
      },
    );
    final syncing = registration.synchronize();
    await entered.future;
    registration.stop();
    pending.complete();
    expect(await syncing, isFalse);
    expect(saved, isEmpty);
    await source.close();
  });

  test(
    'restarting registers the unchanged token for the new runtime',
    () async {
      final source = _Source();
      var registered = 0;
      final registration = MobilePushRegistration(
        source,
        register:
            ({
              required platform,
              required provider,
              required token,
              privacyMode = 'summary',
              forSession,
            }) async {
              registered++;
            },
        unregister: ({forSession}) async {},
      );
      await registration.start(onOpenRoute: (_) {});
      registration.stop();
      await registration.start(onOpenRoute: (_) {});
      expect(registered, 2);
      registration.stop();
      await source.close();
    },
  );

  test('concurrent synchronization coalesces an identical token', () async {
    final source = _Source();
    final pending = Completer<void>();
    var registered = 0;
    final registration = MobilePushRegistration(
      source,
      register:
          ({
            required platform,
            required provider,
            required token,
            privacyMode = 'summary',
            forSession,
          }) async {
            registered++;
            await pending.future;
          },
      unregister: ({forSession}) async {},
    );
    final first = registration.synchronize();
    final second = registration.synchronize();
    await settle();
    pending.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(registered, 1);
    registration.stop();
    await source.close();
  });

  test(
    'resume and token rotation preserve explicitly selected privacy',
    () async {
      final source = _Source();
      final modes = <String>[];
      final registration = MobilePushRegistration(
        source,
        register:
            ({
              required platform,
              required provider,
              required token,
              privacyMode = 'summary',
              forSession,
            }) async {
              modes.add(privacyMode);
            },
        unregister: ({forSession}) async {},
      );
      await registration.start(onOpenRoute: (_) {});
      await registration.synchronize(privacyMode: 'detail');
      await registration.synchronize();
      source.tokens.add(
        const MobilePushToken(
          platform: 'android',
          provider: 'fcm',
          value: 'fixture-rotated',
        ),
      );
      await settle();
      expect(modes, ['summary', 'detail', 'detail']);
      registration.stop();
      await source.close();
    },
  );

  test(
    'stop during initial target lookup suppresses obsolete navigation',
    () async {
      final source = _Source()..initial = Completer<String?>();
      final routes = <String>[];
      final registration = MobilePushRegistration(
        source,
        register: ({
          required platform,
          required provider,
          required token,
          privacyMode = 'summary',
          forSession,
        }) async {},
        unregister: ({forSession}) async {},
      );
      final starting = registration.start(onOpenRoute: routes.add);
      await settle();
      registration.stop();
      source.initial!.complete('/messages');
      await starting;
      expect(routes, isEmpty);
      await source.close();
    },
  );
  test('live rotated token wins over an older pending native lookup', () async {
    final source = _Source()..lookup = Completer<MobilePushToken?>();
    final tokens = <String>[];
    final registration = MobilePushRegistration(
      source,
      register:
          ({
            required platform,
            required provider,
            required token,
            privacyMode = 'summary',
            forSession,
          }) async {
            tokens.add(token);
          },
      unregister: ({forSession}) async {},
    );
    final starting = registration.start(onOpenRoute: (_) {});
    await settle();
    source.tokens.add(
      const MobilePushToken(
        platform: 'android',
        provider: 'fcm',
        value: 'fixture-newest',
      ),
    );
    await settle();
    source.lookup!.complete(_token);
    await starting;
    expect(tokens, ['fixture-newest']);
    registration.stop();
    await source.close();
  });

  test(
    'failed live registration is contained and subsequent resume retries',
    () async {
      final source = _Source();
      var attempts = 0;
      var fail = false;
      final registration = MobilePushRegistration(
        source,
        register:
            ({
              required platform,
              required provider,
              required token,
              privacyMode = 'summary',
              forSession,
            }) async {
              attempts++;
              if (fail) throw StateError('fixture transport unavailable');
            },
        unregister: ({forSession}) async {},
      );
      await registration.start(onOpenRoute: (_) {});
      fail = true;
      source.tokens.add(
        const MobilePushToken(
          platform: 'android',
          provider: 'fcm',
          value: 'fixture-rotated',
        ),
      );
      await settle();
      fail = false;
      expect(await registration.synchronize(privacyMode: 'detail'), isTrue);
      expect(attempts, 3);
      registration.stop();
      await source.close();
    },
  );
}

class _Source implements MobilePushTokenSource {
  Completer<MobilePushToken?>? lookup;
  Completer<String?>? initial;
  final tokens = StreamController<MobilePushToken>.broadcast();
  final clicks = StreamController<String>.broadcast();
  @override
  Future<MobilePushToken?> currentToken() async =>
      lookup == null ? _token : await lookup!.future;
  @override
  Future<String?> initialTargetRoute() async =>
      initial == null ? '/messages' : await initial!.future;
  @override
  Stream<MobilePushToken> get tokenChanges => tokens.stream;
  @override
  Stream<String> get notificationClicks => clicks.stream;
  Future<void> close() async {
    await tokens.close();
    await clicks.close();
  }
}

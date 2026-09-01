import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/notifications/mobile_push_registration.dart';

void main() {
  test('push target routes allow IM and OA destination surfaces', () {
    const conversationId = 'a03da586-7b21-40a9-b130-c3c09d955f74';
    const requestId = 'c28d99b6-8128-492c-ae5b-208974eae30c';
    expect(normalizeMobilePushTargetRoute('/messages'), '/messages');
    expect(normalizeMobilePushTargetRoute('/todos'), '/todos');
    expect(normalizeMobilePushTargetRoute('/notifications'), '/notifications');
    expect(normalizeMobilePushTargetRoute('/contacts'), '/contacts');
    expect(
      normalizeMobilePushTargetRoute('/contacts?mode=requests'),
      '/contacts?mode=requests',
    );
    expect(
      normalizeMobilePushTargetRoute('/chat/$conversationId'),
      '/chat/$conversationId',
    );
    expect(
      normalizeMobilePushTargetRoute('/approval/$requestId'),
      '/approval/$requestId',
    );
    expect(normalizeMobilePushTargetRoute('/chat/not-a-guid'), isNull);
    expect(normalizeMobilePushTargetRoute('/approval/not-a-guid'), isNull);
    expect(normalizeMobilePushTargetRoute('/workbench'), isNull);
    expect(
      normalizeMobilePushTargetRoute('/contacts?mode=organization'),
      isNull,
    );
    expect(
      normalizeMobilePushTargetRoute('/chat/$conversationId?unsafe=true'),
      isNull,
    );
    expect(
      normalizeMobilePushTargetRoute('https://example.com/messages'),
      isNull,
    );
  });

  test('registration consumes initial and live notification targets', () async {
    final source = _FakeMobilePushTokenSource(
      current: const MobilePushToken(
        platform: 'android',
        provider: 'fcm',
        value: 'initial-token',
      ),
      initialRoute: '/messages',
    );
    final registrations = <MobilePushToken>[];
    final routes = <String>[];
    var unregisterCount = 0;
    var securelyStoredToken = '';
    var secureTokenCleared = false;
    final registration = MobilePushRegistration(
      source,
      register:
          ({
            required platform,
            required provider,
            required token,
            privacyMode = 'summary',
          }) async {
            registrations.add(
              MobilePushToken(
                platform: platform,
                provider: provider,
                value: token,
              ),
            );
            expect(privacyMode, 'summary');
          },
      unregister: () async => unregisterCount += 1,
      saveSecureToken: (value) async => securelyStoredToken = value,
      clearSecureToken: () async => secureTokenCleared = true,
    );

    await registration.start(onOpenRoute: routes.add);
    expect(registrations.map((item) => item.value), ['initial-token']);
    expect(securelyStoredToken, contains('initial-token'));
    expect(routes, ['/messages']);

    source.emitToken(
      const MobilePushToken(
        platform: 'android',
        provider: 'fcm',
        value: 'rotated-token',
      ),
    );
    source.emitClick('/chat/a03da586-7b21-40a9-b130-c3c09d955f74');
    await Future<void>.delayed(Duration.zero);
    expect(registrations.map((item) => item.value), [
      'initial-token',
      'rotated-token',
    ]);
    expect(routes.last, '/chat/a03da586-7b21-40a9-b130-c3c09d955f74');

    await registration.synchronize();
    expect(registrations, hasLength(2));
    await registration.unregister();
    expect(unregisterCount, 1);
    expect(secureTokenCleared, isTrue);
    registration.stop();
    await source.close();
  });

  test('privacy changes re-register the same push token', () async {
    final source = _FakeMobilePushTokenSource(
      current: const MobilePushToken(
        platform: 'android',
        provider: 'fcm',
        value: 'stable-token',
      ),
    );
    final privacyModes = <String>[];
    final registration = MobilePushRegistration(
      source,
      register:
          ({
            required platform,
            required provider,
            required token,
            privacyMode = 'summary',
          }) async {
            privacyModes.add(privacyMode);
          },
      unregister: () async {},
    );

    await registration.synchronize();
    await registration.synchronize(privacyMode: 'detail');
    await registration.synchronize(privacyMode: 'detail');

    expect(privacyModes, ['summary', 'detail']);
    registration.stop();
    await source.close();
  });

  test('runtime token provider keeps changes during initial lookup', () async {
    final initialLookup = Completer<MobilePushToken?>();
    final source = _FakeMobilePushTokenSource(
      currentLookup: initialLookup.future,
    );
    final container = ProviderContainer(
      overrides: [mobilePushTokenSourceProvider.overrideWithValue(source)],
    );
    final values = <MobilePushToken?>[];
    final listener = container.listen(mobilePushRuntimeTokenProvider, (
      _,
      next,
    ) {
      if (next.hasValue) values.add(next.value);
    }, fireImmediately: true);
    addTearDown(() async {
      listener.close();
      container.dispose();
      await source.close();
    });

    await Future<void>.delayed(Duration.zero);
    const token = MobilePushToken(
      platform: 'android',
      provider: 'fcm',
      value: 'token-during-lookup',
    );
    source.emitToken(token);
    initialLookup.complete(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(values, [null, token]);
  });
}

final class _FakeMobilePushTokenSource implements MobilePushTokenSource {
  _FakeMobilePushTokenSource({
    this.current,
    this.initialRoute,
    this.currentLookup,
  });

  MobilePushToken? current;
  final String? initialRoute;
  final Future<MobilePushToken?>? currentLookup;
  final _tokens = StreamController<MobilePushToken>.broadcast();
  final _clicks = StreamController<String>.broadcast();

  @override
  Future<MobilePushToken?> currentToken() async =>
      currentLookup == null ? current : await currentLookup;

  @override
  Future<String?> initialTargetRoute() async => initialRoute;

  @override
  Stream<String> get notificationClicks => _clicks.stream;

  @override
  Stream<MobilePushToken> get tokenChanges => _tokens.stream;

  void emitToken(MobilePushToken token) {
    current = token;
    _tokens.add(token);
  }

  void emitClick(String route) => _clicks.add(route);

  Future<void> close() async {
    await _tokens.close();
    await _clicks.close();
  }
}

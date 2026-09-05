import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/notifications/mobile_push_registration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('fixture/push-store');
  const events = EventChannel('fixture/push-events');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('fixture/push-events'),
      null,
    );
  });

  for (final returnedScope in ['test-env', 'production-env', null]) {
    test(
      'native token lookup accepts only matching scope $returnedScope',
      () async {
        messenger.setMockMethodCallHandler(method, (call) async {
          expect(call.method, 'getToken');
          expect(call.arguments, {'storageNamespace': 'test-env'});
          return {
            'platform': 'android',
            'provider': 'fixture',
            'token': 'fixture-token',
            'storageNamespace': ?returnedScope,
          };
        });
        final source = NativeMobilePushTokenSource(
          methodChannel: method,
          storageNamespace: 'test-env',
        );
        final token = await source.currentToken();
        expect(
          token?.value,
          returnedScope == 'test-env' ? 'fixture-token' : null,
        );
      },
    );
  }

  test(
    'native event subscription is scoped and rejects foreign tokens',
    () async {
      messenger.setMockMethodCallHandler(
        const MethodChannel('fixture/push-events'),
        (call) async {
          if (call.method == 'listen') {
            expect(call.arguments, {'storageNamespace': 'test-env'});
          }
          return null;
        },
      );
      final source = NativeMobilePushTokenSource(
        eventChannel: events,
        storageNamespace: 'test-env',
      );
      final received = <MobilePushToken>[];
      final subscription = source.tokenChanges.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      for (final scope in [null, 'production-env', 'test-env']) {
        messenger.handlePlatformMessage(
          'fixture/push-events',
          codec.encodeSuccessEnvelope({
            'type': 'token',
            'platform': 'android',
            'provider': 'fixture',
            'token': 'fixture-token',
            'storageNamespace': ?scope,
          }),
          (_) {},
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      await subscription.cancel();
    },
  );
  test('Android scope migration does not silently disable the existing APNs bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(
      method,
      (_) async => {
        'platform': 'ios',
        'provider': 'apns',
        'token': 'fixture-apns',
      },
    );
    final source = NativeMobilePushTokenSource(
      methodChannel: method,
      storageNamespace: 'test-env',
    );
    expect((await source.currentToken())?.value, 'fixture-apns');
  });
}

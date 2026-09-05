import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/config/app_environment.dart';
import 'package:hexing_terminal_mobile/core/config/app_storage_scope.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppStorageScope scope(
    String url, {
    String name = 'test',
    bool demo = false,
  }) => AppStorageScope(
    controlPlaneUrl: url,
    environmentName: name,
    demoMode: demo,
  );

  test('same environment name on a different server has isolated stores', () {
    final old = scope('http://43.198.199.162');
    final current = scope('http://api.sfhkh.com');
    for (final key in [
      'mobile.session.v1',
      'mobile.credential.v1',
      'mobile.device.id',
      'mobile.push.token.v1',
      'mobile.im.cache-key.v1.account-a',
    ]) {
      expect(current.secureStorageKey(key), isNot(old.secureStorageKey(key)));
      expect(current.secureStorageKey(key), isNot(key));
    }
    for (final feature in ['im', 'oa']) {
      expect(
        current.databaseFileName(feature),
        isNot(old.databaseFileName(feature)),
      );
      expect(
        current.databaseFileName(feature),
        isNot('hexing-mobile-$feature.db'),
      );
    }
    for (final feature in [
      'im-message-images',
      'im-video-previews',
      'mobile-artifacts',
      'managed-tunnel',
    ]) {
      expect(current.directoryName(feature), isNot(old.directoryName(feature)));
    }
    expect(current.namespace, isNot(old.namespace)); // Outbox binary directory.
  });

  test(
    'namespace stays stable across restart and equivalent URL formatting',
    () {
      final expected = scope('http://api.sfhkh.com').namespace;
      expect(scope('http://api.sfhkh.com').namespace, expected);
      expect(scope('http://API.SFHKH.COM:80/').namespace, expected);
      expect(
        scope(' http://api.sfhkh.com/ ', name: ' TEST ').namespace,
        expected,
      );
    },
  );

  test(
    'scheme, port, base path, environment and demo mode remain separate',
    () {
      final namespaces = [
        scope('http://api.sfhkh.com'),
        scope('https://api.sfhkh.com'),
        scope('http://api.sfhkh.com:8080'),
        scope('http://api.sfhkh.com/tenant'),
        scope('http://api.sfhkh.com', name: 'production'),
        scope('http://api.sfhkh.com', demo: true),
      ].map((value) => value.namespace).toSet();
      expect(namespaces, hasLength(6));
    },
  );

  test('sanitized environment labels cannot alias one another', () {
    expect(
      scope('http://localhost', name: 'test/a').namespace,
      isNot(scope('http://localhost', name: 'test?a').namespace),
    );
    expect(
      scope('http://localhost', name: '测试/../').namespace,
      matches(RegExp(r'^[a-z0-9_-]+$')),
    );
  });

  test('invalid or credential-bearing control-plane addresses fail closed', () {
    for (final value in [
      '/relative',
      'file:///tmp',
      'ftp://example.com',
      'https://name@example.com',
      'https://example.com?credential=value',
      'https://example.com#fragment',
    ]) {
      expect(() => scope(value).namespace, throwsFormatException);
    }
  });

  test(
    'old unscoped sessions and remembered credentials are not restored',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'mobile.session.v1':
            '{"accessToken":"old-fixture","userId":"old-account"}',
        'mobile.credential.v1':
            '{"username":"old-account","password":"fixture"}',
        'mobile.device.id': 'old-device-fixture',
        'mobile.push.token.v1': 'old-push-fixture',
      });
      final store = SecureSessionStore();
      expect(await store.readSession(), isNull);
      expect(await store.readCredential(), isNull);
      expect(await store.readDeviceId(), isNull);
      expect(await store.readPushToken(), isNull);
      expect(
        await const FlutterSecureStorage().containsKey(
          key: 'mobile.session.v1',
        ),
        isTrue,
      );
    },
  );

  test(
    'current installation identity persists without reading the old scope',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      await store.saveDeviceId('current-device-fixture');
      final reopened = SecureSessionStore();
      expect(await reopened.readDeviceId(), 'current-device-fixture');
      expect(
        await const FlutterSecureStorage().read(
          key: AppEnvironment.secureStorageKey('mobile.device.id'),
        ),
        'current-device-fixture',
      );
      expect(
        await const FlutterSecureStorage().read(key: 'mobile.device.id'),
        isNull,
      );
      await reopened.clearSession(clearCredential: true);
      expect(
        await SecureSessionStore().readDeviceId(),
        'current-device-fixture',
      );
    },
  );
}

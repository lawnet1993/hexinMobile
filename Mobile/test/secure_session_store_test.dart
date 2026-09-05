import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('password change removes matching credential without removing session', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureSessionStore();
    const session = MobileSession(accessToken: 'fixture', deviceId: 'device',
      userId: 'user', displayName: 'Fixture', username: 'user', policySignatureKey: '', imApiUrl: '', oaApiUrl: '');
    await store.saveSession(session);
    await store.saveCredential('user', 'fixture-old');
    expect(await store.clearCredentialIfMatches('user', 'fixture-old'), isTrue);
    expect(await store.readCredential(), isNull);
    expect(await store.readSession(), same(session));
  });

  for (final entry in [('another-user', 'fixture-old'), ('user', 'fixture-new')]) {
    test('password cleanup preserves nonmatching credential ${entry.$1}', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      await store.saveCredential(entry.$1, entry.$2);
      expect(await store.clearCredentialIfMatches('user', 'fixture-old'), isFalse);
      final saved = await store.readCredential();
      expect(saved?.username == entry.$1 && saved?.password == entry.$2, isTrue);
    });
  }

  test('credential replacement racing cleanup cannot delete a newer password', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureSessionStore();
    await store.saveCredential('user', 'fixture-old');
    await Future.wait([
      store.saveCredential('user', 'fixture-new'),
      store.clearCredentialIfMatches('user', 'fixture-old'),
    ]);
    expect((await store.readCredential())?.password == 'fixture-new', isTrue);
    await Future.wait([
      store.clearCredentialIfMatches('user', 'fixture-new'),
      store.saveCredential('user', 'fixture-newer'),
    ]);
    expect((await store.readCredential())?.password == 'fixture-newer', isTrue);
  });

  test('IM cache keys are stable, random and isolated per account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureSessionStore();

    final first = await store.readOrCreateImCacheKey('account-a');
    final repeated = await store.readOrCreateImCacheKey('account-a');
    final second = await store.readOrCreateImCacheKey('account-b');

    expect(first, hasLength(32));
    expect(repeated, first);
    expect(second, hasLength(32));
    expect(second, isNot(first));
  });

  test('saved session is immediately readable in the same process', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureSessionStore();
    const session = MobileSession(
      accessToken: 'token',
      deviceId: 'device',
      userId: 'user',
      displayName: 'Tester',
      username: 'tester',
      policySignatureKey: 'key',
      imApiUrl: 'https://example.test/api/im',
      oaApiUrl: 'https://example.test/api/oa',
    );

    await store.saveSession(session);

    expect(await store.readSession(), same(session));
  });

  test('session refresh token survives persistence and rotation', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = SecureSessionStore();
    const session = MobileSession(
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
      deviceId: 'server-device',
      installationId: 'installation-device',
      userId: 'user',
      displayName: 'Tester',
      username: 'tester',
      policySignatureKey: 'key',
      imApiUrl: 'https://example.test/api/im',
      oaApiUrl: 'https://example.test/api/oa',
    );

    await store.saveSession(
      session.withTokens(
        accessToken: 'access-new',
        refreshToken: 'refresh-new',
      ),
    );
    final reopened = SecureSessionStore();
    final saved = await reopened.readSession();

    expect(saved?.accessToken, 'access-new');
    expect(saved?.refreshToken, 'refresh-new');
    expect(saved?.deviceId, 'server-device');
    expect(saved?.installationId, 'installation-device');
    expect(saved?.syncDeviceId, 'installation-device');
  });

  test(
    'managed force sign-out clears session and remembered credential',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      await store.saveCredential('tester', 'secret');
      await store.saveSession(
        const MobileSession(
          accessToken: 'token',
          deviceId: 'device',
          userId: 'user',
          displayName: 'Tester',
          username: 'tester',
          policySignatureKey: 'key',
          imApiUrl: '',
          oaApiUrl: '',
        ),
      );

      await store.clearSession(clearCredential: true);

      expect(await store.readSession(), isNull);
      expect(await store.readCredential(), isNull);
    },
  );

  test(
    'password change cleanup prevents reuse of the old credential',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      await store.saveCredential('tester', 'old-password');
      await store.saveSession(
        const MobileSession(
          accessToken: 'token',
          refreshToken: 'refresh-token',
          deviceId: 'device',
          userId: 'user',
          displayName: 'Tester',
          username: 'tester',
          policySignatureKey: 'key',
          imApiUrl: '',
          oaApiUrl: '',
        ),
      );

      await store.clearSession(clearCredential: true);

      expect(await store.readSession(), isNull);
      expect(await store.readCredential(), isNull);
    },
  );
}

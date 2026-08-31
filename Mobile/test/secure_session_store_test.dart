import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      deviceId: 'device',
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
    expect(saved?.deviceId, 'device');
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

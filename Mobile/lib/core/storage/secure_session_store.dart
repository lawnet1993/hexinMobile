import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_environment.dart';

final secureSessionStoreProvider = Provider<SecureSessionStore>(
  (ref) => SecureSessionStore(),
);

final class MobileSession {
  const MobileSession({
    required this.accessToken,
    required this.deviceId,
    this.installationId = '',
    required this.userId,
    required this.displayName,
    required this.username,
    required this.policySignatureKey,
    required this.imApiUrl,
    required this.oaApiUrl,
    this.refreshToken = '',
  });

  factory MobileSession.fromJson(Map<String, Object?> json) => MobileSession(
    accessToken: json['accessToken']?.toString() ?? '',
    deviceId: json['deviceId']?.toString() ?? '',
    installationId:
        json['installationId']?.toString() ??
        json['deviceId']?.toString() ??
        '',
    userId: json['userId']?.toString() ?? '',
    displayName: json['displayName']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    policySignatureKey: json['policySignatureKey']?.toString() ?? '',
    imApiUrl: json['imApiUrl']?.toString() ?? '',
    oaApiUrl: json['oaApiUrl']?.toString() ?? '',
    refreshToken: json['refreshToken']?.toString() ?? '',
  );

  final String accessToken;

  /// Server-confirmed device record id used by authenticated APIs.
  final String deviceId;

  /// Stable per-install id used for login identity and local sync isolation.
  final String installationId;
  final String userId;
  final String displayName;
  final String username;
  final String policySignatureKey;
  final String imApiUrl;
  final String oaApiUrl;
  final String refreshToken;

  MobileSession withTokens({
    required String accessToken,
    String? refreshToken,
  }) => MobileSession(
    accessToken: accessToken,
    deviceId: deviceId,
    installationId: installationId,
    userId: userId,
    displayName: displayName,
    username: username,
    policySignatureKey: policySignatureKey,
    imApiUrl: imApiUrl,
    oaApiUrl: oaApiUrl,
    refreshToken: refreshToken ?? this.refreshToken,
  );

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'deviceId': deviceId,
    'installationId': installationId,
    'userId': userId,
    'displayName': displayName,
    'username': username,
    'policySignatureKey': policySignatureKey,
    'imApiUrl': imApiUrl,
    'oaApiUrl': oaApiUrl,
    'refreshToken': refreshToken,
  };

  String get syncDeviceId =>
      installationId.isNotEmpty ? installationId : deviceId;

  bool isSameSession(MobileSession other) =>
      accessToken == other.accessToken &&
      deviceId == other.deviceId &&
      userId == other.userId;
}

final class SavedCredential {
  const SavedCredential(this.username, this.password);
  final String username;
  final String password;
}

/// A late operation is obsolete, not proof of an expired/new invalid session.
final class SessionChangedException implements Exception {
  const SessionChangedException();

  @override
  String toString() => '登录状态已变更，已取消旧请求';
}

final class SecureSessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static String get _sessionKey =>
      AppEnvironment.secureStorageKey('mobile.session.v1');
  static String get _credentialKey =>
      AppEnvironment.secureStorageKey('mobile.credential.v1');
  static String get _deviceKey =>
      AppEnvironment.secureStorageKey('mobile.device.id');
  static String get _pushTokenKey =>
      AppEnvironment.secureStorageKey('mobile.push.token.v1');
  static String get _imCacheKeyPrefix =>
      AppEnvironment.secureStorageKey('mobile.im.cache-key.v1.');
  final FlutterSecureStorage _storage;
  MobileSession? _cachedSession;
  Future<void> _sessionOperations = Future<void>.value();

  Future<T> _withSessionLock<T>(Future<T> Function() action) {
    final operation = _sessionOperations.then((_) => action());
    _sessionOperations = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<MobileSession?> readSession() => _withSessionLock(_readSession);

  Future<MobileSession?> _readSession() async {
    final cached = _cachedSession;
    if (cached != null) return cached;
    final value = await _storage.read(key: _sessionKey);
    if (value == null || value.isEmpty) return null;
    try {
      final session = MobileSession.fromJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
      );
      _cachedSession = session;
      return session;
    } catch (_) {
      await _storage.delete(key: _sessionKey);
      return null;
    }
  }

  Future<void> saveSession(MobileSession value) =>
      _withSessionLock(() => _saveSession(value));

  Future<void> _saveSession(MobileSession value) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(value.toJson()));
    _cachedSession = value;
  }

  /// Serialize a short account-cache operation with login/logout persistence.
  /// Never perform network I/O or call session methods inside [action].
  Future<T> withCurrentSession<T>(
    MobileSession expected,
    Future<T> Function() action,
  ) => _withSessionLock(() async {
    final current = await _readSession();
    if (current == null || !current.isSameSession(expected)) {
      throw const SessionChangedException();
    }
    return action();
  });

  /// Compare and mutate under the same lock as login persistence. A delayed
  /// response must never delete or replace a subsequently saved session.
  Future<bool> replaceSessionIfCurrent(
    MobileSession expected,
    MobileSession replacement,
  ) => _withSessionLock(() async {
    final current = await _readSession();
    if (current == null || !current.isSameSession(expected)) return false;
    await _saveSession(replacement);
    return true;
  });

  Future<bool> clearSessionIfCurrent(
    MobileSession expected, {
    bool clearCredential = false,
  }) => _withSessionLock(() async {
    final current = await _readSession();
    if (current == null || !current.isSameSession(expected)) return false;
    await clearPushToken();
    await _clearSession(clearCredential: clearCredential);
    return true;
  });

  Future<SavedCredential?> readCredential() async {
    final value = await _storage.read(key: _credentialKey);
    if (value == null || value.isEmpty) return null;
    try {
      final json = (jsonDecode(value) as Map).cast<String, Object?>();
      return SavedCredential(
        json['username']?.toString() ?? '',
        json['password']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCredential(String username, String password) =>
      _withSessionLock(
        () => _storage.write(
          key: _credentialKey,
          value: jsonEncode({'username': username, 'password': password}),
        ),
      );

  /// Remove only the password actually superseded by a successful change.
  /// Serialize with credential writes so a newer login is never erased.
  Future<bool> clearCredentialIfMatches(String username, String password) =>
      _withSessionLock(() async {
        final saved = await readCredential();
        if (saved == null ||
            saved.username != username ||
            saved.password != password) {
          return false;
        }
        await _storage.delete(key: _credentialKey);
        return true;
      });

  /// Stable mobile installation identity. The historical storage key is kept
  /// so an app upgrade never rotates an already bound device unexpectedly.
  Future<String?> readInstallationId() => _storage.read(key: _deviceKey);
  Future<void> saveInstallationId(String value) =>
      _storage.write(key: _deviceKey, value: value);

  Future<String?> readDeviceId() => readInstallationId();
  Future<void> saveDeviceId(String value) => saveInstallationId(value);

  Future<String?> readPushToken() => _storage.read(key: _pushTokenKey);
  Future<void> savePushToken(String value) =>
      _storage.write(key: _pushTokenKey, value: value);
  Future<void> clearPushToken() => _storage.delete(key: _pushTokenKey);

  Future<List<int>> readOrCreateImCacheKey(String accountId) async {
    final key = '$_imCacheKeyPrefix${_storageKeySuffix(accountId)}';
    final existing = await _storage.read(key: key);
    if (existing != null && existing.isNotEmpty) {
      try {
        final bytes = base64Decode(existing);
        if (bytes.length == 32) return bytes;
      } catch (_) {
        // Invalid key material must not be silently rotated over encrypted data.
      }
      throw StateError('IM cache key is invalid for the current account.');
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: key, value: base64Encode(bytes));
    return bytes;
  }

  Future<void> deleteImCacheKey(String accountId) =>
      _storage.delete(key: '$_imCacheKeyPrefix${_storageKeySuffix(accountId)}');

  Future<void> clearCredential() => _storage.delete(key: _credentialKey);

  Future<void> clearSession({bool clearCredential = false}) =>
      _withSessionLock(() => _clearSession(clearCredential: clearCredential));

  Future<void> _clearSession({bool clearCredential = false}) async {
    _cachedSession = null;
    await _storage.delete(key: _sessionKey);
    if (clearCredential) await _storage.delete(key: _credentialKey);
  }

  static String _storageKeySuffix(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}

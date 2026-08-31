import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureSessionStoreProvider = Provider<SecureSessionStore>(
  (ref) => SecureSessionStore(),
);

final class MobileSession {
  const MobileSession({
    required this.accessToken,
    required this.deviceId,
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
    userId: json['userId']?.toString() ?? '',
    displayName: json['displayName']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    policySignatureKey: json['policySignatureKey']?.toString() ?? '',
    imApiUrl: json['imApiUrl']?.toString() ?? '',
    oaApiUrl: json['oaApiUrl']?.toString() ?? '',
    refreshToken: json['refreshToken']?.toString() ?? '',
  );

  final String accessToken;
  final String deviceId;
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
    'userId': userId,
    'displayName': displayName,
    'username': username,
    'policySignatureKey': policySignatureKey,
    'imApiUrl': imApiUrl,
    'oaApiUrl': oaApiUrl,
    'refreshToken': refreshToken,
  };
}

final class SavedCredential {
  const SavedCredential(this.username, this.password);
  final String username;
  final String password;
}

final class SecureSessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'mobile.session.v1';
  static const _credentialKey = 'mobile.credential.v1';
  static const _deviceKey = 'mobile.device.id';
  static const _imCacheKeyPrefix = 'mobile.im.cache-key.v1.';
  final FlutterSecureStorage _storage;
  MobileSession? _cachedSession;

  Future<MobileSession?> readSession() async {
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

  Future<void> saveSession(MobileSession value) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(value.toJson()));
    _cachedSession = value;
  }

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
      _storage.write(
        key: _credentialKey,
        value: jsonEncode({'username': username, 'password': password}),
      );

  Future<String?> readDeviceId() => _storage.read(key: _deviceKey);
  Future<void> saveDeviceId(String value) =>
      _storage.write(key: _deviceKey, value: value);

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

  Future<void> clearSession({bool clearCredential = false}) async {
    _cachedSession = null;
    await _storage.delete(key: _sessionKey);
    if (clearCredential) await _storage.delete(key: _credentialKey);
  }

  static String _storageKeySuffix(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}

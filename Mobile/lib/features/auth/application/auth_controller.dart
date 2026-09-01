import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_session_store.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, MobileSession?>(AuthController.new);

final class LoginFailure implements Exception {
  const LoginFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AuthController extends AsyncNotifier<MobileSession?> {
  Future<MobileSession?>? _refreshing;

  @override
  Future<MobileSession?> build() {
    if (AppEnvironment.demoAutoLogin) {
      return Future.value(
        const MobileSession(
          accessToken: 'demo-token',
          deviceId: '00000000-0000-0000-0000-000000000001',
          userId: '00000000-0000-0000-0000-000000000002',
          displayName: '林晨',
          username: 'term.sh01',
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: '',
        ),
      );
    }
    return ref.read(secureSessionStoreProvider).readSession();
  }

  Future<void> login({
    required String username,
    required String password,
    required bool remember,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _authenticate(username, password, remember: remember),
    );
  }

  Future<MobileSession> _authenticate(
    String username,
    String password, {
    required bool remember,
  }) async {
    final store = ref.read(secureSessionStoreProvider);
    final identity = await _deviceIdentity(store);
    final package = await PackageInfo.fromPlatform();
    try {
      final response = await ref
          .read(dioProvider)
          .post<Map<String, Object?>>(
            '/api/client/login',
            data: {
              'username': username.trim(),
              'password': password,
              'deviceId': identity.id,
              'deviceName': identity.name,
              'fingerprint': identity.fingerprint,
              'operatingSystem': identity.operatingSystem,
              'clientVersion': package.version,
              'region': '',
            },
          );
      final body = response.data ?? const <String, Object?>{};
      final device = _map(body['device']);
      final collaboration = _map(body['collaboration']);
      final session = MobileSession(
        accessToken: body['accessToken']?.toString() ?? '',
        deviceId: device['id']?.toString() ?? identity.id,
        userId: device['userId']?.toString() ?? '',
        displayName: username.trim(),
        username: username.trim(),
        policySignatureKey: body['policySignatureKey']?.toString() ?? '',
        imApiUrl: collaboration['imApiUrl']?.toString() ?? '',
        oaApiUrl: collaboration['oaApiUrl']?.toString() ?? '',
        refreshToken:
            body['refreshToken']?.toString() ??
            body['refresh_token']?.toString() ??
            '',
      );
      if (session.accessToken.isEmpty || session.deviceId.isEmpty) {
        throw const LoginFailure('登录响应不完整，请稍后重试');
      }
      await store.saveSession(session);
      if (remember) {
        await store.saveCredential(username.trim(), password);
      }
      return session;
    } on DioException catch (error) {
      throw LoginFailure(_loginError(error));
    }
  }

  Future<SavedCredential?> savedCredential() =>
      ref.read(secureSessionStoreProvider).readCredential();

  Future<void> clearSavedCredential() =>
      ref.read(secureSessionStoreProvider).clearCredential();

  Future<MobileSession?> refreshSession({bool forceCredential = false}) async {
    final active = _refreshing;
    if (active != null) {
      final refreshed = !forceCredential
          ? await active
          : await active.then((_) => _refreshSession(forceCredential: true));
      if (refreshed != null) state = AsyncData(refreshed);
      return refreshed;
    }
    final refresh = _refreshSession(forceCredential: forceCredential);
    _refreshing = refresh;
    try {
      final refreshed = await refresh;
      if (refreshed != null) state = AsyncData(refreshed);
      return refreshed;
    } finally {
      if (identical(_refreshing, refresh)) _refreshing = null;
    }
  }

  Future<MobileSession?> _refreshSession({
    required bool forceCredential,
  }) async {
    final store = ref.read(secureSessionStoreProvider);
    final current = await store.readSession();
    if (current == null) return null;

    if (!forceCredential && current.refreshToken.isNotEmpty) {
      try {
        final response =
            await Dio(
              BaseOptions(
                baseUrl: AppEnvironment.controlPlaneUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
              ),
            ).post<Map<String, Object?>>(
              '/connect/token',
              data: {
                'grant_type': 'refresh_token',
                'refresh_token': current.refreshToken,
              },
              options: Options(
                contentType: Headers.formUrlEncodedContentType,
                headers: const {'Accept': 'application/json'},
              ),
            );
        final body = response.data ?? const <String, Object?>{};
        final accessToken =
            body['access_token']?.toString() ??
            body['accessToken']?.toString() ??
            '';
        if (accessToken.isNotEmpty) {
          final refreshed = current.withTokens(
            accessToken: accessToken,
            refreshToken:
                body['refresh_token']?.toString() ??
                body['refreshToken']?.toString(),
          );
          await store.saveSession(refreshed);
          return refreshed;
        }
      } on DioException {
        // Match the desktop terminal: fall back to remembered credentials.
      }
    }

    final credential = await store.readCredential();
    if (credential == null || credential.password.isEmpty) return null;
    return _authenticate(
      credential.username,
      credential.password,
      remember: true,
    );
  }

  Future<void> logout({bool clearCredential = false}) async {
    await ref
        .read(secureSessionStoreProvider)
        .clearSession(clearCredential: clearCredential);
    state = const AsyncData(null);
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : <String, Object?>{};

  static String _loginError(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final detail = body is Map
        ? (body['message'] ?? body['error_description'] ?? body['error'])
              ?.toString()
        : null;
    if (status == 401) return '账号或密码错误';
    if (status == 403) {
      return detail?.isNotEmpty == true ? detail! : '当前账号已停用或无终端权限';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError) {
      return '无法连接服务，请检查网络后重试';
    }
    return detail?.isNotEmpty == true ? detail! : '登录失败，请稍后重试';
  }

  Future<_DeviceIdentity> _deviceIdentity(SecureSessionStore store) async {
    final info = DeviceInfoPlugin();
    final existingId = await store.readDeviceId();
    final id = existingId?.isNotEmpty == true ? existingId! : const Uuid().v4();
    if (existingId == null) await store.saveDeviceId(id);

    if (kIsWeb) {
      return _DeviceIdentity(
        id: id,
        name: 'Web 预览终端',
        fingerprint: sha256.convert(utf8.encode('web|$id')).toString(),
        operatingSystem: 'Web',
      );
    }

    var name = '移动终端';
    var source = id;
    var operatingSystem = Platform.operatingSystem;
    if (Platform.isAndroid) {
      final value = await info.androidInfo;
      name = '${value.brand} ${value.model}'.trim();
      source = '${value.id}|${value.brand}|${value.model}|$id';
      operatingSystem = 'Android ${value.version.release}';
    } else if (Platform.isIOS) {
      final value = await info.iosInfo;
      name = value.name;
      source = '${value.identifierForVendor}|${value.utsname.machine}|$id';
      operatingSystem = '${value.systemName} ${value.systemVersion}';
    }
    return _DeviceIdentity(
      id: id,
      name: name,
      fingerprint: sha256.convert(utf8.encode(source)).toString(),
      operatingSystem: operatingSystem,
    );
  }
}

final class _DeviceIdentity {
  const _DeviceIdentity({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.operatingSystem,
  });
  final String id;
  final String name;
  final String fingerprint;
  final String operatingSystem;
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/device/mobile_device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/collaboration_client.dart';
import '../../../core/storage/secure_session_store.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, MobileSession?>(AuthController.new);

final sessionTerminationNoticeProvider =
    NotifierProvider<SessionTerminationNoticeController, String?>(
      SessionTerminationNoticeController.new,
    );

final class SessionTerminationNoticeController extends Notifier<String?> {
  @override
  String? build() => null;

  void showOnce(String message) => state ??= message;

  String? take() {
    final value = state;
    state = null;
    return value;
  }

  void clear() => state = null;
}

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
    ref.read(sessionTerminationNoticeProvider.notifier).clear();
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
    final identity = await ref.read(mobileDeviceIdentityProvider).resolve();
    try {
      final response = await ref
          .read(dioProvider)
          .post<Map<String, Object?>>(
            '/api/client/login',
            data: buildMobileLoginRequest(
              username: username,
              password: password,
              identity: identity,
            ),
          );
      final body = response.data ?? const <String, Object?>{};
      final device = _map(body['device']);
      final collaboration = _map(body['collaboration']);
      final serverDeviceId = device['id']?.toString().trim() ?? '';
      final session = MobileSession(
        accessToken: body['accessToken']?.toString() ?? '',
        deviceId: serverDeviceId.isNotEmpty ? serverDeviceId : identity.id,
        installationId: identity.id,
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

  Future<MobileSession?> refreshSession() async {
    final active = _refreshing;
    if (active != null) {
      final refreshed = await active;
      if (refreshed != null) state = AsyncData(refreshed);
      return refreshed;
    }
    final refresh = _refreshSession();
    _refreshing = refresh;
    try {
      final refreshed = await refresh;
      if (refreshed != null) state = AsyncData(refreshed);
      return refreshed;
    } finally {
      if (identical(_refreshing, refresh)) _refreshing = null;
    }
  }

  Future<MobileSession?> _refreshSession() async {
    final store = ref.read(secureSessionStoreProvider);
    final current = await store.readSession();
    if (current == null) return null;

    if (current.refreshToken.isNotEmpty) {
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
        return null;
      }
    }
    return null;
  }

  Future<void> logout({bool clearCredential = false}) async {
    final store = ref.read(secureSessionStoreProvider);
    final current = await store.readSession();
    try {
      if (current != null && current.imApiUrl.trim().isNotEmpty) {
        await Dio(
          BaseOptions(
            baseUrl: collaborationOrigin(current.imApiUrl, '/api/im'),
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            headers: <String, Object?>{
              'Authorization': 'Bearer ${current.accessToken}',
              'X-Device-Id': current.deviceId,
              'X-Terminal-Device-Id': current.deviceId,
              'X-Terminal-Account-Id': current.userId,
            },
          ),
        ).delete<void>('/api/im/push/devices/current');
      }
    } on DioException {
      // Logging out must remain possible while the push endpoint is offline.
    }
    await store.clearPushToken();
    await store.clearSession(clearCredential: clearCredential);
    state = const AsyncData(null);
  }

  Future<void> terminateSession({required String message}) async {
    final store = ref.read(secureSessionStoreProvider);
    if (await store.readSession() == null && state.value == null) return;
    await store.clearPushToken();
    await store.clearSession();
    ref.read(sessionTerminationNoticeProvider.notifier).showOnce(message);
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
}

Map<String, Object?> buildMobileLoginRequest({
  required String username,
  required String password,
  required MobileDeviceIdentity identity,
}) => <String, Object?>{
  'username': username.trim(),
  'password': password,
  'clientPlatform': 'mobile',
  'deviceId': identity.id,
  'deviceName': identity.name,
  'fingerprint': identity.fingerprint,
  'operatingSystem': identity.operatingSystem,
  'clientVersion': identity.clientVersion,
  'region': '',
};

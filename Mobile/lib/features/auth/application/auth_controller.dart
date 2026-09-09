import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/diagnostics/mobile_startup_diagnostics.dart';
import '../../../core/device/mobile_device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/collaboration_client.dart';
import '../../../core/storage/secure_session_store.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, MobileSession?>(AuthController.new);

final sessionRefreshClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final sessionRefreshClientProvider = Provider<Dio>((ref) {
  final client = Dio(
    BaseOptions(
      baseUrl: AppEnvironment.controlPlaneUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      // Refresh credentials must never be forwarded to a redirected endpoint.
      followRedirects: false,
    ),
  );
  ref.onDispose(() => client.close(force: true));
  return client;
});

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
  ({MobileSession session, Future<MobileSession?> result})? _refreshing;
  ({MobileSession session, DateTime at})? _lastProactiveRefresh;
  MobileSession? _proactiveRefreshRejected;
  String? _expiryToken;
  DateTime? _refreshDueAt;

  @override
  Future<MobileSession?> build() async {
    if (AppEnvironment.demoAutoLogin) {
      const session = MobileSession(
        accessToken: 'demo-token',
        deviceId: '00000000-0000-0000-0000-000000000001',
        userId: '00000000-0000-0000-0000-000000000002',
        displayName: '林晨',
        username: 'term.sh01',
        policySignatureKey: '',
        imApiUrl: '',
        oaApiUrl: '',
      );
      MobileStartupDiagnostics.markCurrent(
        MobileStartupStage.secureSessionHydrated,
      );
      return session;
    }
    final session = await ref.read(secureSessionStoreProvider).readSession();
    MobileStartupDiagnostics.markCurrent(
      MobileStartupStage.secureSessionHydrated,
    );
    return session;
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

  /// Called before the normal heartbeat, including restored login and resume.
  /// The unverified JWT expiry is only a scheduling hint: authentication still
  /// depends on the server. No token/opaque expiry ever causes local logout.
  Future<MobileSession?> maintainSession() async {
    final store = ref.read(secureSessionStoreProvider);
    final current = await store.readSession();
    if (!ref.mounted || state.isLoading || current == null) return current;
    if (current.refreshToken.isEmpty) return current;
    if (_expiryToken != current.accessToken) {
      _expiryToken = current.accessToken;
      _refreshDueAt = sessionRefreshDueAt(current.accessToken);
    }
    final due = _refreshDueAt;
    final now = ref.read(sessionRefreshClockProvider)();
    if (due == null || now.isBefore(due)) return current;
    if (_proactiveRefreshRejected?.isSameSession(current) == true) {
      return current;
    }
    // Share refresh-token rotation with a concurrent authenticated 401. Do
    // this before the retry cooldown so the heartbeat waits for that result.
    final active = _refreshing;
    final alreadyRefreshing = active?.session.isSameSession(current) == true;
    final previous = _lastProactiveRefresh;
    if (!alreadyRefreshing &&
        previous != null &&
        previous.session.isSameSession(current) &&
        !now.isBefore(previous.at) &&
        now.difference(previous.at) < const Duration(seconds: 30)) {
      return current;
    }
    _lastProactiveRefresh = (session: current, at: now);
    try {
      final refreshed = await refreshSession(expectedSession: current);
      if (refreshed == null) {
        // A rejected proactive refresh must not discard an otherwise valid
        // access token. The next real 401/replacement remains authoritative.
        _proactiveRefreshRejected = current;
      }
    } on DioException {
      // Timeout, offline and 5xx retry on a later heartbeat/resume. Do not
      // replace the session, clear local data, or show repeated login prompts.
    }
    return store.readSession();
  }

  Future<MobileSession?> refreshSession({
    MobileSession? expectedSession,
  }) async {
    final current = await ref.read(secureSessionStoreProvider).readSession();
    if (current == null) return null;
    if (expectedSession != null && !current.isSameSession(expectedSession)) {
      return current;
    }
    final active = _refreshing;
    if (active != null && active.session.isSameSession(current)) {
      return active.result;
    }
    final refresh = _refreshSession(current);
    _refreshing = (session: current, result: refresh);
    try {
      return await refresh;
    } finally {
      if (identical(_refreshing?.result, refresh)) _refreshing = null;
    }
  }

  Future<MobileSession?> _refreshSession(MobileSession current) async {
    final store = ref.read(secureSessionStoreProvider);

    if (current.refreshToken.isNotEmpty) {
      try {
        final response = await ref
            .read(sessionRefreshClientProvider)
            .post<Map<String, Object?>>(
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
          if (await store.replaceSessionIfCurrent(current, refreshed)) {
            _recordSessionRefresh(response.statusCode, body, 'accepted');
            if (ref.mounted && !state.isLoading) state = AsyncData(refreshed);
            return refreshed;
          }
          _recordSessionRefresh(response.statusCode, body, 'stale_result');
          return await store.readSession();
        }
        _recordSessionRefresh(response.statusCode, body, 'invalid_response');
      } on DioException catch (error) {
        // A refresh network failure does not establish session expiry.
        if (error.response?.statusCode == 400 ||
            error.response?.statusCode == 401) {
          _recordSessionRefresh(
            error.response?.statusCode,
            error.response?.data,
            'rejected',
          );
          return null;
        }
        _recordSessionRefresh(
          error.response?.statusCode,
          error.response?.data,
          'retry',
        );
        rethrow;
      }
    }
    return null;
  }

  Future<void> logout({
    bool clearCredential = false,
    MobileSession? expectedSession,
  }) async {
    final store = ref.read(secureSessionStoreProvider);
    final current = await store.readSession();
    if (expectedSession != null &&
        (current == null || !current.isSameSession(expectedSession))) {
      return;
    }
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
    if (current != null &&
        await store.clearSessionIfCurrent(
          current,
          clearCredential: clearCredential,
        )) {
      if (ref.mounted && !state.isLoading) state = const AsyncData(null);
    }
  }

  Future<bool> terminateSession({
    required String message,
    MobileSession? expectedSession,
  }) async {
    final store = ref.read(secureSessionStoreProvider);
    final current = expectedSession ?? await store.readSession();
    if (current == null || !await store.clearSessionIfCurrent(current)) {
      return false;
    }
    if (ref.mounted && !state.isLoading) {
      ref.read(sessionTerminationNoticeProvider.notifier).showOnce(message);
      state = const AsyncData(null);
    }
    return true;
  }

  /// Only the credentials actually used by the failed request may be revoked.
  /// Comparing account/device alone is insufficient after same-account login.
  Future<bool> handleSessionFailure(DioException error) async {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final code = body is Map
        ? (body['code'] ?? body['Code'])?.toString().trim().toLowerCase()
        : '';
    final replaced = status == 409 && code == 'session_replaced';
    if (status != 401 && !replaced) return false;
    final current = await ref.read(secureSessionStoreProvider).readSession();
    if (current == null || !requestUsedSession(error.requestOptions, current)) {
      _recordSessionFailure(error, 'ignored_stale_response');
      return false;
    }
    if (!replaced && current.refreshToken.isNotEmpty) {
      try {
        if (await refreshSession(expectedSession: current) != null) {
          _recordSessionFailure(error, 'session_preserved');
          return false;
        }
      } on DioException {
        _recordSessionFailure(error, 'refresh_retry');
        return false;
      }
    }
    final terminated = await terminateSession(
      expectedSession: current,
      message: replaced ? '当前移动端已在另一台设备登录，请重新登录' : '登录已失效或已到期，请重新登录',
    );
    _recordSessionFailure(
      error,
      terminated ? 'terminated' : 'ignored_stale_response',
    );
    return terminated;
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

@visibleForTesting
DateTime? sessionRefreshDueAt(String token) {
  try {
    if (token.length > 16384) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final body = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (body is! Map) return null;
    final expiry = body['exp'];
    if (expiry is! int || expiry < 0 || expiry >= 100000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      expiry * 1000,
      isUtc: true,
    ).subtract(const Duration(minutes: 5));
  } catch (_) {
    return null;
  }
}

void _recordSessionRefresh(int? status, Object? body, String action) {
  // A server error description/code may echo credentials. Never log it raw.
  final error = body is Map ? body['error'] : null;
  const allowed = {
    'invalid_client',
    'invalid_grant',
    'invalid_request',
    'unauthorized_client',
    'unsupported_grant_type',
    'server_error',
    'temporarily_unavailable',
  };
  final code = error == null
      ? null
      : allowed.contains(error)
      ? error
      : 'unrecognized';
  debugPrint(
    'MOBILE_SESSION_REFRESH ${jsonEncode({'status': status, 'errorCode': code, 'action': action})}',
  );
}

void _recordSessionFailure(DioException error, String action) {
  // Whitelist metadata only. No headers, identities, query or response bodies.
  final source = switch (error.requestOptions.path) {
    '/api/client/heartbeat' => 'heartbeat',
    '/api/client/commands' => 'managed_commands',
    '/api/client/sites' => 'managed_sites',
    '/api/im/sync/events' => 'im_events',
    _ => 'authenticated_request',
  };
  debugPrint(
    'MOBILE_SESSION_AUTH ${jsonEncode({'source': source, 'status': error.response?.statusCode, 'action': action})}',
  );
}

bool requestUsedSession(RequestOptions request, MobileSession session) {
  String header(String name) {
    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value?.toString() ?? '';
    }
    return '';
  }

  return session.accessToken.isNotEmpty &&
      header('authorization') == 'Bearer ${session.accessToken}' &&
      header('x-device-id') == session.deviceId;
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
  'installationId': identity.installationId,
  'deviceName': identity.name,
  'fingerprint': identity.fingerprint,
  'operatingSystem': identity.operatingSystem,
  'clientVersion': identity.clientVersion,
  'region': '',
};

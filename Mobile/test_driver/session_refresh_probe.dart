// Explicit test-only entrypoint: exercises the real app refresh once for test03.
// It may rotate tokens through the supported refresh protocol; never exports them.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hexing_terminal_mobile/core/config/app_environment.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/main.dart' as app;

import 'session_health_probe.dart' show tokenTimeHints;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && const bool.fromEnvironment('UAT_VERIFY_REFRESH')) {
    try {
      debugPrint('AI_UAT_SESSION_REFRESH ${jsonEncode(await verifyRefresh())}');
    } catch (_) {
      debugPrint('AI_UAT_SESSION_REFRESH {"probe":"unavailable"}');
    }
  }
  await app.main();
}

Future<Map<String, Object?>> verifyRefresh() async {
  final sessions = SecureSessionStore();
  final before = await sessions.readSession();
  final origin = Uri.parse(AppEnvironment.controlPlaneUrl);
  if (before == null ||
      before.username != 'test03' ||
      origin.host != 'api.sfhkh.com' ||
      origin.userInfo.isNotEmpty ||
      !const ['http', 'https'].contains(origin.scheme)) {
    throw StateError('Authorized test03 session required');
  }
  final container = ProviderContainer(
    overrides: [secureSessionStoreProvider.overrideWithValue(sessions)],
  );
  final result = <String, Object?>{
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
    'beforeTimes': tokenTimeHints(before.accessToken),
    'hasRefreshToken': before.refreshToken.isNotEmpty,
  };
  try {
    await container.read(authControllerProvider.future);
    final dio = container.read(sessionRefreshClientProvider);
    dio.options.followRedirects = false;
    dio.interceptors.add(
      InterceptorsWrapper(
        onResponse: (response, handler) {
          result['response'] = safeRefreshResponse(
            response.statusCode,
            response.data,
          );
          handler.next(response);
        },
        onError: (error, handler) {
          result['response'] = safeRefreshResponse(
            error.response?.statusCode,
            error.response?.data,
          );
          result['transport'] = error.type.name;
          handler.next(error);
        },
      ),
    );
    try {
      final refreshed = await container
          .read(authControllerProvider.notifier)
          .refreshSession(expectedSession: before);
      result['refreshReturnedSession'] = refreshed != null;
    } catch (_) {
      result['refreshThrew'] = true;
    }
    final after = await sessions.readSession();
    result['sessionPreserved'] = after != null;
    result['sameAccountAndDevice'] =
        after?.userId == before.userId && after?.deviceId == before.deviceId;
    result['accessTokenChanged'] =
        after != null && after.accessToken != before.accessToken;
    result['refreshTokenChanged'] =
        after != null && after.refreshToken != before.refreshToken;
    if (after != null) result['afterTimes'] = tokenTimeHints(after.accessToken);
  } finally {
    container.dispose();
  }
  return result;
}

Map<String, Object?> safeRefreshResponse(int? status, Object? raw) {
  final body = raw is Map ? raw : const {};
  final error = body['error'];
  const known = {
    'invalid_client',
    'invalid_grant',
    'invalid_request',
    'unauthorized_client',
    'unsupported_grant_type',
    'server_error',
    'temporarily_unavailable',
  };
  return {
    'status': status,
    'errorCode': error == null
        ? null
        : known.contains(error)
        ? error
        : 'unrecognized',
    'hasAccessToken': (body['access_token'] ?? body['accessToken']) is String,
    'hasRefreshToken':
        (body['refresh_token'] ?? body['refreshToken']) is String,
  };
}

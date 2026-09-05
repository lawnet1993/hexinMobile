// Test-only, read-only diagnostics. Never imported by the normal entrypoint.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hexing_terminal_mobile/core/config/app_environment.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/main.dart' as app;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    try {
      final result = await inspectSessionHealth();
      debugPrint('AI_UAT_SESSION_HEALTH ${jsonEncode(result)}');
    } catch (_) {
      debugPrint('AI_UAT_SESSION_HEALTH {"probe":"unavailable"}');
    }
  }
  await app.main();
}

Future<Map<String, Object?>> inspectSessionHealth() async {
  final session = await SecureSessionStore().readSession();
  if (session == null ||
      !const ['test01', 'test03'].contains(session.username)) {
    throw StateError('Authorized test session required');
  }
  final origin = Uri.parse(AppEnvironment.controlPlaneUrl);
  if (origin.host != 'api.sfhkh.com' ||
      !const ['http', 'https'].contains(origin.scheme) ||
      origin.userInfo.isNotEmpty) {
    throw StateError('Authorized test origin required');
  }
  final result = <String, Object?>{
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
    'hasRefreshToken': session.refreshToken.isNotEmpty,
    'tokenTimes': tokenTimeHints(session.accessToken),
  };
  final dio = Dio(
    BaseOptions(
      baseUrl: origin.toString(),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      followRedirects: false,
      validateStatus: (_) => true,
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'X-Device-Id': session.deviceId,
        'X-Terminal-Device-Id': session.deviceId,
        'X-Terminal-Account-Id': session.userId,
      },
    ),
  );
  try {
    for (final entry in const {
      'commands': '/api/client/commands',
      'imBootstrap': '/api/im/bootstrap',
      'oaBootstrap': '/api/oa/bootstrap',
    }.entries) {
      try {
        final response = await dio.get<Object?>(
          entry.value,
          queryParameters: entry.key == 'commands'
              ? {'deviceId': session.deviceId}
              : null,
        );
        result[entry.key] = {'status': response.statusCode};
      } on DioException catch (error) {
        result[entry.key] = {
          'status': error.response?.statusCode,
          'transport': error.type.name,
        };
      }
    }
  } finally {
    dio.close(force: true);
  }
  return result;
}

// JWT claims are unverified hints only; never decide authentication with them.
// Explicit numeric whitelist: no account/device claims, signature or token text.
Map<String, Object?> tokenTimeHints(String token) {
  try {
    if (token.length > 16384) return {'available': false};
    final parts = token.split('.');
    if (parts.length != 3) return {'available': false};
    final body = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (body is! Map) return {'available': false};
    final result = <String, Object?>{'verified': false};
    for (final claim in ['iat', 'nbf', 'exp']) {
      final value = body[claim];
      if (value is int && value >= 0 && value < 100000000000) {
        result[claim] = DateTime.fromMillisecondsSinceEpoch(
          value * 1000,
          isUtc: true,
        ).toIso8601String();
      }
    }
    result['available'] = result.length > 1;
    return result;
  } catch (_) {
    return {'available': false};
  }
}

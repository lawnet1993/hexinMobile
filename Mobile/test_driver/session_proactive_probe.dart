// Explicit test-only harness. Moves only the injected scheduling clock into
// the due window; never changes the OS clock, persisted token or server time.
// Uses the real presence -> maintainSession -> refresh -> heartbeat path.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hexing_terminal_mobile/core/config/app_environment.dart';
import 'package:hexing_terminal_mobile/core/network/api_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/mobile_presence_coordinator.dart';
import 'package:hexing_terminal_mobile/main.dart' as app;

import 'session_health_probe.dart' show tokenTimeHints;
import 'session_refresh_probe.dart' show safeRefreshResponse;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && const bool.fromEnvironment('UAT_VERIFY_PROACTIVE')) {
    try {
      debugPrint(
        'AI_UAT_SESSION_PROACTIVE ${jsonEncode(await verifyProactiveRefresh())}',
      );
    } catch (_) {
      debugPrint('AI_UAT_SESSION_PROACTIVE {"probe":"unavailable"}');
    }
  }
  await app.main();
}

Future<Map<String, Object?>> verifyProactiveRefresh() async {
  final store = SecureSessionStore();
  final before = await store.readSession();
  final origin = Uri.parse(AppEnvironment.controlPlaneUrl);
  if (before == null ||
      before.username != 'test03' ||
      origin.host != 'api.sfhkh.com' ||
      origin.userInfo.isNotEmpty ||
      !const ['http', 'https'].contains(origin.scheme)) {
    throw StateError('Authorized test03 session required');
  }
  final beforeTimes = tokenTimeHints(before.accessToken);
  final expiry = DateTime.tryParse(beforeTimes['exp']?.toString() ?? '');
  if (expiry == null || before.refreshToken.isEmpty) {
    throw StateError('Existing refresh-capable test session required');
  }
  final scheduledAt = expiry.subtract(const Duration(minutes: 4));
  final result = <String, Object?>{
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
    'scheduleClockOnly': scheduledAt.toIso8601String(),
    'naturalExpiryTest': false,
    'beforeTimes': beforeTimes,
  };
  final container = ProviderContainer(
    overrides: [
      secureSessionStoreProvider.overrideWithValue(store),
      sessionRefreshClockProvider.overrideWithValue(() => scheduledAt),
    ],
  );
  final order = <String>[];
  var refreshCalls = 0;
  try {
    await container.read(authControllerProvider.future);
    container
        .read(sessionRefreshClientProvider)
        .interceptors
        .add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              refreshCalls++;
              order.add('refresh');
              handler.next(request);
            },
            onResponse: (response, handler) {
              result['refreshResponse'] = safeRefreshResponse(
                response.statusCode,
                response.data,
              );
              handler.next(response);
            },
            onError: (error, handler) {
              result['refreshResponse'] = safeRefreshResponse(
                error.response?.statusCode,
                error.response?.data,
              );
              handler.next(error);
            },
          ),
        );
    container
        .read(dioProvider)
        .interceptors
        .add(
          InterceptorsWrapper(
            onResponse: (response, handler) {
              if (response.requestOptions.path == '/api/client/heartbeat') {
                order.add('heartbeat');
                result['heartbeatStatus'] = response.statusCode;
                result['heartbeatUsedChangedToken'] =
                    response.requestOptions.headers['Authorization'] !=
                    'Bearer ${before.accessToken}';
              }
              handler.next(response);
            },
            onError: (error, handler) {
              if (error.requestOptions.path == '/api/client/heartbeat') {
                result['heartbeatStatus'] = error.response?.statusCode;
                result['heartbeatTransport'] = error.type.name;
              }
              handler.next(error);
            },
          ),
        );
    final presence = container.read(mobilePresenceCoordinatorProvider);
    await presence.synchronizeNow();
    final after = await store.readSession();
    result['sessionPreserved'] = after != null;
    result['sameAccountAndDevice'] =
        after?.userId == before.userId &&
        after?.deviceId == before.deviceId &&
        after?.syncDeviceId == before.syncDeviceId;
    result['accessTokenChanged'] =
        after != null && after.accessToken != before.accessToken;
    result['refreshTokenChanged'] =
        after != null && after.refreshToken != before.refreshToken;
    if (after != null) result['afterTimes'] = tokenTimeHints(after.accessToken);
    await presence.synchronizeNow();
    result['refreshCallsIncludingRepeat'] = refreshCalls;
    result['order'] = order;
    result['loginNotice'] =
        container.read(sessionTerminationNoticeProvider) != null;
    return result;
  } finally {
    container.dispose();
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../storage/secure_session_store.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppEnvironment.controlPlaneUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final session = await ref
            .read(secureSessionStoreProvider)
            .readSession();
        if (session != null && session.accessToken.isNotEmpty) {
          // Preserve credentials pinned to a device/account request snapshot.
          options.headers.putIfAbsent(
            'Authorization',
            () => 'Bearer ${session.accessToken}',
          );
          options.headers.putIfAbsent('X-Device-Id', () => session.deviceId);
        }
        handler.next(options);
      },
    ),
  );
  return dio;
});

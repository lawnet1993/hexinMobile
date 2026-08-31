import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_session_store.dart';
import '../domain/mobile_tunnel_profile.dart';

final mobileTunnelRepositoryProvider = Provider<MobileTunnelRepository>(
  (ref) => MobileTunnelRepository(
    ref.read(dioProvider),
    ref.read(secureSessionStoreProvider),
  ),
);

final class MobileTunnelRepository {
  const MobileTunnelRepository(this._dio, this._sessionStore);

  final Dio _dio;
  final SecureSessionStore _sessionStore;

  Future<MobileTunnelProfileLookup> fetchProfile(
    TunnelRuntimeIdentity runtime,
  ) async {
    final session = await _sessionStore.readSession();
    if (session == null || session.deviceId.isEmpty) {
      throw const MobileTunnelException('登录状态已失效');
    }
    final response = await _dio.post<Map<String, Object?>>(
      '/api/client/mobile-tunnel/profile',
      data: <String, Object?>{
        'deviceId': session.deviceId,
        'platform': runtime.platform,
        'architecture': runtime.architecture,
        'coreVersion': runtime.coreVersion,
        'coreSha256': runtime.coreSha256,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return MobileTunnelProfileLookup.fromJson(
      response.data ?? const <String, Object?>{},
    );
  }
}

final class MobileTunnelException implements Exception {
  const MobileTunnelException(this.message);
  final String message;
  @override
  String toString() => message;
}

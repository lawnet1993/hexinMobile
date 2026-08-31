import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_session_store.dart';

final collaborationClientProvider = Provider<CollaborationClient>((ref) {
  return CollaborationClient(ref.read(secureSessionStoreProvider));
});

final class CollaborationClient {
  CollaborationClient(this._sessionStore);

  final SecureSessionStore _sessionStore;

  Future<Dio> forIm() =>
      _create((session) => session.imApiUrl, servicePrefix: '/api/im');
  Future<Dio> forOa() =>
      _create((session) => session.oaApiUrl, servicePrefix: '/api/oa');

  Future<Dio> _create(
    String Function(MobileSession session) selectUrl, {
    required String servicePrefix,
  }) async {
    final session = await _sessionStore.readSession();
    if (session == null) {
      throw StateError('登录状态已失效，请重新登录');
    }
    final baseUrl = selectUrl(session).trim();
    if (baseUrl.isEmpty) {
      throw StateError('协作服务尚未配置');
    }
    if (session.userId.isEmpty) {
      throw StateError('登录状态已失效，请重新登录');
    }
    return Dio(
      BaseOptions(
        baseUrl: collaborationOrigin(baseUrl, servicePrefix),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: <String, Object?>{
          'Accept': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
          'X-Device-Id': session.deviceId,
          'X-Terminal-Device-Id': session.deviceId,
          'X-Terminal-Account-Id': session.userId,
        },
      ),
    );
  }
}

/// Returns the server origin used by repositories whose request paths already
/// include `/api/im` or `/api/oa`.
///
/// The login contract may return either the deployment origin or a
/// service-scoped URL. Normalising both forms here prevents a duplicated path
/// such as `/api/im/api/im/bootstrap` while keeping repository paths aligned
/// with the Windows client and server routes.
String collaborationOrigin(String rawBaseUrl, String servicePrefix) {
  final uri = Uri.parse(rawBaseUrl.trim());
  final normalizedPrefix =
      '/${servicePrefix.split('/').where((p) => p.isNotEmpty).join('/')}';
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.endsWith(normalizedPrefix)) {
    path = path.substring(0, path.length - normalizedPrefix.length);
  }
  return uri
      .replace(path: path, query: null, fragment: null)
      .toString()
      .replaceFirst(RegExp(r'/+$'), '');
}

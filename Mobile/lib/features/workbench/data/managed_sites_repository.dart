import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';

final managedSitesRepositoryProvider = Provider<ManagedSitesRepository>((ref) {
  return ManagedSitesRepository(ref.read(dioProvider));
});

final managedSiteResolverProvider = Provider<ManagedSiteResolver>((ref) {
  return ManagedSiteResolver();
});

final managedSitesProvider = FutureProvider<List<ManagedAccessSite>>((
  ref,
) async {
  if (AppEnvironment.demoMode) return const [];
  final session = ref.watch(authControllerProvider).value;
  final deviceId = session?.deviceId ?? '';
  if (deviceId.isEmpty) return const [];
  final repository = ref.read(managedSitesRepositoryProvider);
  try {
    return await repository.sites(deviceId, forSession: session);
  } on ManagedSitesSessionExpired catch (error) {
    if (error.failure != null && ref.mounted) {
      await ref
          .read(authControllerProvider.notifier)
          .handleSessionFailure(error.failure!);
    }
    rethrow;
  }
}, retry: (_, _) => null);

final class ManagedSitesRepository {
  const ManagedSitesRepository(this._dio);

  final Dio _dio;

  Future<List<ManagedAccessSite>> sites(
    String deviceId, {
    MobileSession? forSession,
  }) async {
    late final Response<List<Object?>> response;
    try {
      response = await _dio.get<List<Object?>>(
        '/api/client/sites',
        queryParameters: {'deviceId': deviceId},
        options: Options(
          headers: forSession == null
              ? null
              : {
                  'Authorization': 'Bearer ${forSession.accessToken}',
                  'X-Device-Id': forSession.deviceId,
                },
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw ManagedSitesSessionExpired(error);
      }
      rethrow;
    }
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ManagedAccessSite.fromJson(item.cast<String, Object?>()))
        .where((site) => site.id.isNotEmpty && site.name.isNotEmpty)
        .toList();
  }
}

final class ManagedSitesSessionExpired implements Exception {
  const ManagedSitesSessionExpired([this.failure]);
  final DioException? failure;

  @override
  String toString() => '授权站点会话校验失败，请下拉重试';
}

final class ManagedAccessSite {
  const ManagedAccessSite({
    required this.id,
    required this.name,
    required this.category,
    required this.departmentName,
    required this.primaryDomain,
    required this.loginUrl,
    required this.backupDomains,
    required this.backupLoginUrls,
  });

  factory ManagedAccessSite.fromJson(Map<String, Object?> json) =>
      ManagedAccessSite(
        id: _text(json, 'id'),
        name: _text(json, 'name'),
        category: _text(json, 'category'),
        departmentName: _text(json, 'departmentName'),
        primaryDomain: _text(json, 'primaryDomain'),
        loginUrl: _text(json, 'loginUrl'),
        backupDomains: _text(json, 'backupDomains'),
        backupLoginUrls: _textList(json, 'backupLoginUrls'),
      );

  final String id;
  final String name;
  final String category;
  final String departmentName;
  final String primaryDomain;
  final String loginUrl;
  final String backupDomains;
  final List<String> backupLoginUrls;
}

final class ManagedSiteResolution {
  const ManagedSiteResolution({required this.uri, required this.usedBackup});

  final Uri uri;
  final bool usedBackup;
}

final class ManagedSiteResolver {
  ManagedSiteResolver({Dio? probeClient})
    : _probeClient =
          probeClient ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              followRedirects: true,
              maxRedirects: 5,
              responseType: ResponseType.stream,
              validateStatus: (_) => true,
            ),
          );

  final Dio _probeClient;

  Future<ManagedSiteResolution> resolve(ManagedAccessSite site) async {
    final candidates = <({String value, bool usedBackup})>[
      (value: site.loginUrl, usedBackup: false),
      ...site.backupLoginUrls.map((value) => (value: value, usedBackup: true)),
    ];
    for (final candidate in candidates) {
      final uri = _authorizedHttpUri(candidate.value);
      if (uri == null) continue;
      try {
        final response = await _probeClient.getUri<Object?>(uri);
        final status = response.statusCode ?? 0;
        if ((status >= 200 && status < 400) ||
            const {401, 403, 405}.contains(status)) {
          return ManagedSiteResolution(
            uri: uri,
            usedBackup: candidate.usedBackup,
          );
        }
      } on DioException {
        // Continue with the next centrally authorised address.
      }
    }
    throw const ManagedSiteUnavailable();
  }
}

final class ManagedSiteUnavailable implements Exception {
  const ManagedSiteUnavailable();

  @override
  String toString() => '站点主备地址均不可用，请稍后重试或联系管理员';
}

Uri? _authorizedHttpUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    return null;
  }
  return uri;
}

String _text(Map<String, Object?> json, String key) =>
    (json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'])
        ?.toString()
        .trim() ??
    '';

List<String> _textList(Map<String, Object?> json, String key) {
  final value = json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

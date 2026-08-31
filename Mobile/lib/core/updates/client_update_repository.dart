import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../network/api_client.dart';
import '../storage/secure_session_store.dart';

final clientUpdateRepositoryProvider = Provider<ClientUpdateRepository>((ref) {
  return ClientUpdateRepository(
    ref.read(dioProvider),
    ref.read(secureSessionStoreProvider),
  );
});

final clientUpdateInfoProvider = FutureProvider.autoDispose<ClientUpdateInfo>(
  (ref) => ref
      .read(clientUpdateRepositoryProvider)
      .fetchLatest()
      .timeout(const Duration(seconds: 12)),
);

final class ClientUpdateRepository {
  const ClientUpdateRepository(this._dio, this._sessionStore);

  final Dio _dio;
  final SecureSessionStore _sessionStore;

  Future<ClientUpdateInfo?> checkLatest() async {
    final info = await fetchLatest();
    return info.hasPublishedVersion && info.updateAvailable ? info : null;
  }

  Future<ClientUpdateInfo> fetchLatest() async {
    final session = await _sessionStore.readSession();
    final package = await PackageInfo.fromPlatform();
    final response = await _dio.get<Map<String, Object?>>(
      session == null
          ? '/api/client/versions/public/latest'
          : '/api/client/versions/latest',
      queryParameters: {
        if (session != null) 'deviceId': session.deviceId,
        'currentVersion': package.version,
        'product': 'terminal-mobile',
        'channel': 'stable',
        'platform': _platform(),
        'architecture': 'universal',
      },
      options: Options(
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    final body = response.data ?? const <String, Object?>{};
    return ClientUpdateInfo.fromJson(body);
  }

  static String _platform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return Platform.operatingSystem;
  }
}

final class ClientUpdateInfo {
  const ClientUpdateInfo({
    required this.hasPublishedVersion,
    required this.updateAvailable,
    required this.isMandatory,
    required this.releaseId,
    required this.latestVersion,
    required this.packageUrl,
    required this.packageSize,
    required this.releaseNotes,
  });

  final bool hasPublishedVersion;
  final bool updateAvailable;
  final bool isMandatory;
  final String releaseId;
  final String latestVersion;
  final String packageUrl;
  final int packageSize;
  final String releaseNotes;

  factory ClientUpdateInfo.fromJson(Map<String, Object?> json) =>
      ClientUpdateInfo(
        hasPublishedVersion: json['hasPublishedVersion'] == true,
        updateAvailable: json['updateAvailable'] == true,
        isMandatory: json['isMandatory'] == true,
        releaseId: json['releaseId']?.toString() ?? '',
        latestVersion: json['latestVersion']?.toString() ?? '',
        packageUrl: json['packageUrl']?.toString() ?? '',
        packageSize: (json['packageSize'] as num?)?.toInt() ?? 0,
        releaseNotes: json['releaseNotes']?.toString() ?? '',
      );
}

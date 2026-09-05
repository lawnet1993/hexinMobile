import 'package:flutter/foundation.dart';

import 'app_storage_scope.dart';

final class AppEnvironment {
  const AppEnvironment._();

  static const controlPlaneUrl = String.fromEnvironment(
    'CONTROL_PLANE_URL',
    defaultValue: 'http://api.sfhkh.com',
  );
  static const demoMode = bool.fromEnvironment('DEMO_MODE');
  static const demoAutoLogin = bool.fromEnvironment('DEMO_AUTO_LOGIN');
  static const demoDataDelayMilliseconds = int.fromEnvironment(
    'DEMO_DATA_DELAY_MS',
  );
  static const channel = String.fromEnvironment(
    'RELEASE_CHANNEL',
    defaultValue: 'stable',
  );
  static const environmentName = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'test',
  );

  static final storageScope = AppStorageScope(
    environmentName: environmentName,
    controlPlaneUrl: controlPlaneUrl,
    demoMode: demoMode,
  );

  static String get storageNamespace => storageScope.namespace;

  static String secureStorageKey(String legacyKey) =>
      storageScope.secureStorageKey(legacyKey);

  static String databaseFileName(String feature) =>
      storageScope.databaseFileName(feature);

  static String storageDirectoryName(String feature) =>
      storageScope.directoryName(feature);

  static const _releaseArtifactPublicKeys = String.fromEnvironment(
    'MOBILE_ARTIFACT_PUBLIC_KEYS',
  );

  static Map<String, String> get mobileArtifactPublicKeys {
    final raw = _releaseArtifactPublicKeys.isNotEmpty
        ? _releaseArtifactPublicKeys
        : (kDebugMode
              ? 'mobile-development-1:11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
              : '');
    return Map.unmodifiable(
      Map.fromEntries(
        raw
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && item.contains(':'))
            .map((item) {
              final separator = item.indexOf(':');
              return MapEntry(
                item.substring(0, separator).trim(),
                item.substring(separator + 1).trim(),
              );
            })
            .where((entry) => entry.key.isNotEmpty && entry.value.isNotEmpty),
      ),
    );
  }
}

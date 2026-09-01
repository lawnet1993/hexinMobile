import 'package:flutter/foundation.dart';

final class AppEnvironment {
  const AppEnvironment._();

  static const controlPlaneUrl = String.fromEnvironment(
    'CONTROL_PLANE_URL',
    defaultValue: 'http://43.198.199.162',
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

  static String get storageNamespace {
    final normalized = environmentName.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '-',
    );
    return normalized.isEmpty ? 'test' : normalized;
  }

  static String secureStorageKey(String legacyKey) =>
      storageNamespace == 'test' ? legacyKey : '$storageNamespace.$legacyKey';

  static String databaseFileName(String feature) => storageNamespace == 'test'
      ? 'hexing-mobile-$feature.db'
      : 'hexing-mobile-$storageNamespace-$feature.db';

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

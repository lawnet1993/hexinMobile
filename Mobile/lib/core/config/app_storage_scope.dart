import 'dart:convert';

import 'package:crypto/crypto.dart';

/// No implicit migration: another server must never inherit credentials,
/// event cursors or queued business operations from this installation.
final class AppStorageScope {
  AppStorageScope({
    required this.environmentName,
    required this.controlPlaneUrl,
    this.demoMode = false,
  });

  final String environmentName;
  final String controlPlaneUrl;
  final bool demoMode;

  late final String namespace = _namespace();

  String secureStorageKey(String key) => '$namespace.$key';

  String databaseFileName(String feature) =>
      'hexing-mobile-$namespace-$feature.db';

  String directoryName(String feature) => '$feature-$namespace';

  String _namespace() {
    final uri = Uri.parse(controlPlaneUrl.trim());
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid control-plane base URL.');
    }
    final origin = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.replaceFirst(RegExp(r'/+$'), ''),
    ).toString();
    final configuredName = environmentName.trim().toLowerCase();
    final name = configuredName.isEmpty ? 'test' : configuredName;
    final label = name.replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
    final digest = sha256.convert(
      utf8.encode(jsonEncode([name, origin, demoMode])),
    );
    final shortLabel = label.length > 32 ? label.substring(0, 32) : label;
    return '$shortLabel-${digest.toString().substring(0, 24)}';
  }
}

enum MobileArtifactKind {
  managedBrowser,
  configuration;

  String get wireName => switch (this) {
    MobileArtifactKind.managedBrowser => 'managedBrowser',
    MobileArtifactKind.configuration => 'configuration',
  };

  static MobileArtifactKind parse(Object? value) {
    final text = value?.toString().trim();
    return switch (text) {
      'managedBrowser' ||
      'managed-browser' ||
      'browser' => MobileArtifactKind.managedBrowser,
      'configuration' || 'config' => MobileArtifactKind.configuration,
      _ => throw FormatException('Unsupported artifact kind: $value'),
    };
  }
}

final class MobileArtifactManifest {
  const MobileArtifactManifest({
    required this.id,
    required this.kind,
    required this.version,
    required this.platform,
    required this.architecture,
    required this.url,
    required this.sha256,
    required this.size,
    required this.signature,
    required this.signatureAlgorithm,
    required this.keyId,
    required this.publishedAt,
  });

  factory MobileArtifactManifest.fromJson(Map<String, Object?> json) {
    final url = _string(json['url']);
    _validateUrl(url);
    final sha256 = _string(json['sha256']).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const FormatException('Artifact sha256 is invalid.');
    }
    final size = _integer(json['size']);
    if (size <= 0) {
      throw const FormatException('Artifact size must be positive.');
    }
    return MobileArtifactManifest(
      id: _string(json['id']),
      kind: MobileArtifactKind.parse(json['kind']),
      version: _string(json['version']),
      platform: _string(json['platform']),
      architecture: _string(json['architecture']),
      url: url,
      sha256: sha256,
      size: size,
      signature: _string(json['signature']),
      signatureAlgorithm: _string(json['signatureAlgorithm']),
      keyId: _string(json['keyId']),
      publishedAt: _date(json['publishedAt']),
    );
  }

  final String id;
  final MobileArtifactKind kind;
  final String version;
  final String platform;
  final String architecture;
  final String url;
  final String sha256;
  final int size;
  final String signature;
  final String signatureAlgorithm;
  final String keyId;
  final DateTime publishedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.wireName,
    'version': version,
    'platform': platform,
    'architecture': architecture,
    'url': url,
    'sha256': sha256,
    'size': size,
    'signature': signature,
    'signatureAlgorithm': signatureAlgorithm,
    'keyId': keyId,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
  };

  String get signedPayload =>
      '$id\n${kind.wireName}\n$version\n$platform\n$architecture\n$url\n$sha256\n$size\n${publishedAt.toUtc().toIso8601String()}';

  static void _validateUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Artifact URL is invalid.');
    }
    if (uri.scheme == 'https') return;
    if (uri.scheme == 'http' &&
        (uri.host == '127.0.0.1' ||
            uri.host == 'localhost' ||
            uri.host == '::1')) {
      return;
    }
    throw const FormatException('Artifact URL must use HTTPS.');
  }
}

final class MobileArtifactRelease {
  const MobileArtifactRelease({required this.manifest, required this.filePath});

  final MobileArtifactManifest manifest;
  final String filePath;
}

String _string(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    throw const FormatException('Artifact field is required.');
  }
  return text;
}

int _integer(Object? value) => switch (value) {
  int result => result,
  num result => result.toInt(),
  String text => int.parse(text),
  _ => throw const FormatException('Artifact integer field is invalid.'),
};

DateTime _date(Object? value) {
  final result = DateTime.tryParse(_string(value));
  if (result == null) {
    throw const FormatException('Artifact date field is invalid.');
  }
  return result.toUtc();
}

final class MobileTunnelProfile {
  const MobileTunnelProfile({
    required this.profileId,
    required this.profileVersion,
    required this.displayName,
    required this.allowBackground,
    required this.configBase64,
    required this.configSha256,
    required this.coreVersion,
    required this.coreSha256,
    required this.signatureKeyId,
    required this.signedPayload,
    required this.signature,
    required this.signatureAlgorithm,
    required this.publishedAt,
  });

  factory MobileTunnelProfile.fromJson(Map<String, Object?> json) =>
      MobileTunnelProfile(
        profileId: json['profileId']?.toString() ?? '',
        profileVersion: json['profileVersion']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '企业安全网络',
        allowBackground: json['allowBackground'] == true,
        configBase64: json['configBase64']?.toString() ?? '',
        configSha256: json['configSha256']?.toString() ?? '',
        coreVersion: json['coreVersion']?.toString() ?? '',
        coreSha256: json['coreSha256']?.toString() ?? '',
        signatureKeyId: json['signatureKeyId']?.toString() ?? '',
        signedPayload: json['signedPayload']?.toString() ?? '',
        signature: json['signature']?.toString() ?? '',
        signatureAlgorithm: json['signatureAlgorithm']?.toString() ?? '',
        publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      );

  final String profileId;
  final String profileVersion;
  final String displayName;
  final bool allowBackground;
  final String configBase64;
  final String configSha256;
  final String coreVersion;
  final String coreSha256;
  final String signatureKeyId;
  final String signedPayload;
  final String signature;
  final String signatureAlgorithm;
  final DateTime? publishedAt;
}

final class MobileTunnelProfileLookup {
  const MobileTunnelProfileLookup({required this.isAuthorized, this.profile});

  factory MobileTunnelProfileLookup.fromJson(Map<String, Object?> json) {
    final profile = json['profile'];
    return MobileTunnelProfileLookup(
      isAuthorized: json['isAuthorized'] == true,
      profile: profile is Map
          ? MobileTunnelProfile.fromJson(profile.cast<String, Object?>())
          : null,
    );
  }

  final bool isAuthorized;
  final MobileTunnelProfile? profile;
}

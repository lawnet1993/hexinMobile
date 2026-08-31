import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import '../../../core/config/app_environment.dart';
import '../data/mobile_tunnel_repository.dart';
import '../domain/mobile_tunnel_profile.dart';

final class VerifiedTunnelProfile {
  const VerifiedTunnelProfile({
    required this.profile,
    required this.configBytes,
  });
  final MobileTunnelProfile profile;
  final List<int> configBytes;
}

final class TunnelProfileVerifier {
  const TunnelProfileVerifier();

  Future<VerifiedTunnelProfile> verify(
    MobileTunnelProfile profile,
    TunnelRuntimeIdentity runtime,
  ) async {
    _require(profile.profileId.isNotEmpty, '配置标识为空');
    _require(profile.profileVersion.isNotEmpty, '配置版本为空');
    _require(profile.signatureAlgorithm.toLowerCase() == 'ed25519', '签名算法不受支持');
    _require(profile.coreVersion == runtime.coreVersion, '内核版本与安装包不一致');
    _require(_sameHash(profile.coreSha256, runtime.coreSha256), '内核哈希与安装包不一致');

    final configBytes = _decode(profile.configBase64, '配置内容');
    _require(
      _sameHash(sha256.convert(configBytes).toString(), profile.configSha256),
      '配置哈希校验失败',
    );
    final payload = _decode(profile.signedPayload, '签名载荷');
    final signature = _decode(profile.signature, '配置签名');
    final encodedKey =
        AppEnvironment.mobileArtifactPublicKeys[profile.signatureKeyId];
    _require(encodedKey != null, '签名密钥不受信任');
    final publicKey = _decode(encodedKey!, '签名公钥');
    _require(publicKey.length == 32 && signature.length == 64, '签名材料格式无效');

    final valid = await Ed25519().verify(
      payload,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    _require(valid, '配置签名校验失败');
    final payloadJson = _jsonObject(payload);
    final expected = <String, String>{
      'profileId': profile.profileId,
      'profileVersion': profile.profileVersion,
      'configSha256': profile.configSha256,
      'coreVersion': profile.coreVersion,
      'coreSha256': profile.coreSha256,
      'signatureKeyId': profile.signatureKeyId,
    };
    for (final entry in expected.entries) {
      _require(payloadJson[entry.key]?.toString() == entry.value, '签名载荷与配置不一致');
    }
    return VerifiedTunnelProfile(profile: profile, configBytes: configBytes);
  }

  static Map<String, Object?> _jsonObject(List<int> bytes) {
    try {
      return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    } catch (_) {
      throw const MobileTunnelException('签名载荷格式无效');
    }
  }

  static List<int> _decode(String value, String label) {
    try {
      return base64Decode(value.trim());
    } catch (_) {
      throw MobileTunnelException('$label格式无效');
    }
  }

  static bool _sameHash(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();

  static void _require(bool condition, String message) {
    if (!condition) throw MobileTunnelException(message);
  }
}

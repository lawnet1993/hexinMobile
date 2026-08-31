import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'mobile_artifact.dart';

final class ArtifactVerificationException implements Exception {
  const ArtifactVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ArtifactSignatureVerifier {
  Future<void> verify(MobileArtifactManifest manifest);
}

final class Ed25519ArtifactSignatureVerifier
    implements ArtifactSignatureVerifier {
  Ed25519ArtifactSignatureVerifier(this.publicKeys);

  final Map<String, String> publicKeys;
  final Ed25519 _algorithm = Ed25519();

  @override
  Future<void> verify(MobileArtifactManifest manifest) async {
    if (manifest.signatureAlgorithm.toLowerCase() != 'ed25519') {
      throw ArtifactVerificationException(
        '不支持的制品签名算法：${manifest.signatureAlgorithm}',
      );
    }
    final publicKeyText = publicKeys[manifest.keyId];
    if (publicKeyText == null || publicKeyText.isEmpty) {
      throw ArtifactVerificationException('未配置制品签名公钥：${manifest.keyId}');
    }
    final publicKey = SimplePublicKey(
      base64Decode(publicKeyText),
      type: KeyPairType.ed25519,
    );
    final verified = await _algorithm.verify(
      utf8.encode(manifest.signedPayload),
      signature: Signature(
        base64Decode(manifest.signature),
        publicKey: publicKey,
      ),
    );
    if (!verified) {
      throw const ArtifactVerificationException('制品签名校验失败。');
    }
  }
}

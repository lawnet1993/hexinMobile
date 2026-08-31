import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/network/application/tunnel_profile_verifier.dart';
import 'package:hexing_terminal_mobile/features/network/data/mobile_tunnel_repository.dart';
import 'package:hexing_terminal_mobile/features/network/domain/mobile_tunnel_profile.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

void main() {
  const runtime = TunnelRuntimeIdentity(
    platform: 'android',
    architecture: 'arm64-v8a',
    coreVersion: 'mihomo-80362fc1895d+flclash-7c831855efed',
    coreSha256:
        '756b84d021bd9f9201a9d9920516fbfa1e34033f37a08ff038c25b949b60d5ea',
    corePath: '/data/app/lib/libclash.so',
  );

  test('accepts the pinned development key and matching hashes', () async {
    final profile = await _signedProfile(runtime);
    final verified = await const TunnelProfileVerifier().verify(
      profile,
      runtime,
    );
    expect(utf8.decode(verified.configBytes), contains('mixed-port'));
  });

  test('rejects config content modified after signing', () async {
    final profile = await _signedProfile(runtime);
    final tampered = _copy(
      profile,
      configBase64: base64Encode(utf8.encode('{"mixed-port":7891}')),
    );
    await expectLater(
      const TunnelProfileVerifier().verify(tampered, runtime),
      throwsA(
        isA<MobileTunnelException>().having(
          (value) => value.message,
          'message',
          contains('哈希'),
        ),
      ),
    );
  });

  test('rejects a signature that no longer matches the payload', () async {
    final profile = await _signedProfile(runtime);
    final signature = base64Decode(profile.signature)..[0] ^= 0xff;
    await expectLater(
      const TunnelProfileVerifier().verify(
        _copy(profile, signature: base64Encode(signature)),
        runtime,
      ),
      throwsA(
        isA<MobileTunnelException>().having(
          (value) => value.message,
          'message',
          contains('签名'),
        ),
      ),
    );
  });

  test('rejects a profile for a different embedded core', () async {
    final profile = await _signedProfile(runtime);
    const differentRuntime = TunnelRuntimeIdentity(
      platform: 'android',
      architecture: 'arm64-v8a',
      coreVersion: 'other-core',
      coreSha256:
          '756b84d021bd9f9201a9d9920516fbfa1e34033f37a08ff038c25b949b60d5ea',
      corePath: '/data/app/lib/libclash.so',
    );
    await expectLater(
      const TunnelProfileVerifier().verify(profile, differentRuntime),
      throwsA(isA<MobileTunnelException>()),
    );
  });
}

Future<MobileTunnelProfile> _signedProfile(
  TunnelRuntimeIdentity runtime,
) async {
  final config = utf8.encode('{"mixed-port":7890,"rules":["MATCH,DIRECT"]}');
  final configHash = sha256.convert(config).toString();
  final payload = utf8.encode(
    jsonEncode(<String, Object?>{
      'profileId': 'managed-mobile',
      'profileVersion': '2026.08.14.1',
      'configSha256': configHash,
      'coreVersion': runtime.coreVersion,
      'coreSha256': runtime.coreSha256,
      'signatureKeyId': 'mobile-development-1',
    }),
  );
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(
    base64Decode('nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A='),
  );
  final signature = await algorithm.sign(payload, keyPair: keyPair);
  return MobileTunnelProfile(
    profileId: 'managed-mobile',
    profileVersion: '2026.08.14.1',
    displayName: '企业安全网络',
    allowBackground: true,
    configBase64: base64Encode(config),
    configSha256: configHash,
    coreVersion: runtime.coreVersion,
    coreSha256: runtime.coreSha256,
    signatureKeyId: 'mobile-development-1',
    signedPayload: base64Encode(payload),
    signature: base64Encode(signature.bytes),
    signatureAlgorithm: 'ed25519',
    publishedAt: DateTime.utc(2026, 8, 14),
  );
}

MobileTunnelProfile _copy(
  MobileTunnelProfile value, {
  String? configBase64,
  String? signature,
}) => MobileTunnelProfile(
  profileId: value.profileId,
  profileVersion: value.profileVersion,
  displayName: value.displayName,
  allowBackground: value.allowBackground,
  configBase64: configBase64 ?? value.configBase64,
  configSha256: value.configSha256,
  coreVersion: value.coreVersion,
  coreSha256: value.coreSha256,
  signatureKeyId: value.signatureKeyId,
  signedPayload: value.signedPayload,
  signature: signature ?? value.signature,
  signatureAlgorithm: value.signatureAlgorithm,
  publishedAt: value.publishedAt,
);

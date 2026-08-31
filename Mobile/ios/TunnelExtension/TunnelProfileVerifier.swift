import CryptoKit
import Foundation
import NetworkExtension

struct VerifiedTunnelProfile {
  let profileId: String
  let profileVersion: String
  let configPath: String
  let configSha256: String
  let coreVersion: String
  let coreSha256: String
  let signatureKeyId: String
  let signedPayload: String
  let signature: String
}

struct TunnelProfileVerifier {
  func loadAndVerify(
    _ configuration: NEVPNProtocol?,
    bundle: Bundle
  ) throws -> VerifiedTunnelProfile {
    guard let values = configuration?.providerConfiguration else {
      throw TunnelError.invalidProfile("缺少安全配置")
    }
    let profile = try VerifiedTunnelProfile(
      profileId: required(values, "profileId"),
      profileVersion: required(values, "profileVersion"),
      configPath: required(values, "configPath"),
      configSha256: requiredHash(values, "configSha256"),
      coreVersion: required(values, "coreVersion"),
      coreSha256: requiredHash(values, "coreSha256"),
      signatureKeyId: required(values, "signatureKeyId"),
      signedPayload: required(values, "signedPayload"),
      signature: required(values, "signature"))
    guard required(values, "signatureAlgorithm").lowercased() == "ed25519" else {
      throw TunnelError.invalidProfile("仅接受 Ed25519 签名")
    }

    let configHash = try FileHash.sha256(URL(fileURLWithPath: profile.configPath))
    guard secureEqual(configHash, profile.configSha256) else {
      throw TunnelError.artifactVerificationFailed("配置文件哈希不一致")
    }
    let embeddedVersion = bundleValue(bundle, "MobileMihomoCoreVersion")
    let embeddedHash = bundleValue(bundle, "MobileMihomoCoreSha256").lowercased()
    guard embeddedVersion == profile.coreVersion,
          embeddedHash.count == 64,
          secureEqual(embeddedHash, profile.coreSha256)
    else { throw TunnelError.artifactVerificationFailed("mihomo 内核身份不一致") }

    guard let payload = Data(base64Encoded: profile.signedPayload),
          let signature = Data(base64Encoded: profile.signature),
          let publicKey = trustedKeys(bundle)[profile.signatureKeyId]
    else { throw TunnelError.artifactVerificationFailed("签名材料无效") }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard key.isValidSignature(signature, for: payload) else {
      throw TunnelError.artifactVerificationFailed("配置签名无效")
    }
    guard let signed = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
    else { throw TunnelError.artifactVerificationFailed("签名载荷格式无效") }
    let expected = [
      "profileId": profile.profileId,
      "profileVersion": profile.profileVersion,
      "configSha256": profile.configSha256,
      "coreVersion": profile.coreVersion,
      "coreSha256": profile.coreSha256,
      "signatureKeyId": profile.signatureKeyId,
    ]
    for (key, value) in expected where string(signed[key]) != value {
      throw TunnelError.artifactVerificationFailed("签名载荷与配置不一致: \(key)")
    }
    return profile
  }

  private func required(_ values: [String: Any], _ key: String) throws -> String {
    let value = string(values[key])
    guard !value.isEmpty else { throw TunnelError.invalidProfile("\(key) 无效") }
    return value
  }

  private func requiredHash(_ values: [String: Any], _ key: String) throws -> String {
    let value = try required(values, key).lowercased()
    guard value.count == 64, value.allSatisfy(\.isHexDigit) else {
      throw TunnelError.invalidProfile("\(key) 不是 SHA-256")
    }
    return value
  }

  private func trustedKeys(_ bundle: Bundle) -> [String: Data] {
    let raw = bundleValue(bundle, "MobileArtifactSigningPublicKeys")
    return Dictionary(uniqueKeysWithValues: raw.split(separator: ",").compactMap { entry in
      let value = String(entry)
      guard let separator = value.firstIndex(of: ":") else { return nil }
      let keyId = String(value[..<separator]).trimmingCharacters(in: .whitespaces)
      let encoded = String(value[value.index(after: separator)...])
      guard !keyId.isEmpty, let data = Data(base64Encoded: encoded), data.count == 32 else {
        return nil
      }
      return (keyId, data)
    })
  }
}

enum FileHash {
  static func sha256(_ url: URL) throws -> String {
    guard let stream = InputStream(url: url) else {
      throw TunnelError.artifactVerificationFailed("文件不可读取")
    }
    stream.open()
    defer { stream.close() }
    var digest = SHA256()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count < 0 { throw stream.streamError ?? TunnelError.artifactVerificationFailed("文件读取失败") }
      if count == 0 { break }
      digest.update(data: Data(buffer[0..<count]))
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

enum TunnelError: LocalizedError {
  case invalidProfile(String)
  case artifactVerificationFailed(String)
  case coreFailure(String)
  case tunnelFileDescriptorUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidProfile(let message), .artifactVerificationFailed(let message),
         .coreFailure(let message): return message
    case .tunnelFileDescriptorUnavailable: return "无法取得系统隧道接口"
    }
  }
}

func bundleValue(_ bundle: Bundle, _ key: String) -> String {
  (bundle.object(forInfoDictionaryKey: key) as? String)?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func string(_ value: Any?) -> String {
  (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

private func secureEqual(_ left: String, _ right: String) -> Bool {
  let lhs = Array(left.lowercased().utf8)
  let rhs = Array(right.lowercased().utf8)
  guard lhs.count == rhs.count else { return false }
  return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}

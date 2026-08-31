import Darwin
import Foundation
import MihomoCore
import NetworkExtension

/// Stable adapter over the pinned FlClash C ABI. The generated XCFramework is
/// built by scripts/Build-MobileMihomoAppleCore.sh and never updated in place.
final class MihomoCoreAdapter {
  private let profile: VerifiedTunnelProfile
  private weak var provider: PacketTunnelProvider?
  private let homeDirectory: URL
  private var callback: CoreCallback?
  private var started = false

  init(profile: VerifiedTunnelProfile, provider: PacketTunnelProvider) throws {
    self.profile = profile
    self.provider = provider
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.hexing.zhilian.hexingTerminalMobile")
    else { throw TunnelError.coreFailure("App Group 尚未配置") }
    homeDirectory = container.appendingPathComponent("secure-tunnel/runtime", isDirectory: true)
    CoreCallbacks.install()
  }

  func start() throws {
    guard let provider else { throw TunnelError.coreFailure("隧道服务不可用") }
    try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    try installConfiguration()
    try prepareCore()
    try applyNetworkSettings(provider)
    let descriptor = try TunnelFileDescriptor.resolve()
    let callback = CoreCallback(provider: provider)
    self.callback = callback
    let opaque = Unmanaged.passRetained(callback).toOpaque()
    let started = withDuplicatedCString("gvisor") { stack in
      withDuplicatedCString("172.19.0.1/30") { address in
        withDuplicatedCString("172.19.0.2") { dns in
          startTUN(opaque, descriptor, stack, address, dns) != 0
        }
      }
    }
    guard started else {
      Unmanaged<CoreCallback>.fromOpaque(opaque).release()
      self.callback = nil
      throw TunnelError.coreFailure("mihomo TUN 接入失败")
    }
    self.started = true
  }

  func stop() {
    if started { stopTun() }
    started = false
    callback = nil
  }

  func setSuspended(_ value: Bool) {
    guard started else { return }
    suspend(value ? 1 : 0)
  }

  private func installConfiguration() throws {
    let source = URL(fileURLWithPath: profile.configPath)
    let destination = homeDirectory.appendingPathComponent("config.yaml")
    let temporary = homeDirectory.appendingPathComponent("config.yaml.installing")
    try? FileManager.default.removeItem(at: temporary)
    try FileManager.default.copyItem(at: source, to: temporary)
    if FileManager.default.fileExists(atPath: destination.path) {
      _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    } else {
      try FileManager.default.moveItem(at: temporary, to: destination)
    }
  }

  private func prepareCore() throws {
    let initPayload = try JSONSerialization.data(withJSONObject: [
      "home-dir": homeDirectory.path,
      "version": 1,
    ])
    let setupPayload = try JSONSerialization.data(withJSONObject: [
      "selected-map": [:],
      "test-url": "https://www.gstatic.com/generate_204",
    ])
    let signal = DispatchSemaphore(value: 0)
    var result = ""
    let box = CoreCallback { value in result = value; signal.signal() }
    let opaque = Unmanaged.passRetained(box).toOpaque()
    withDuplicatedCString(String(decoding: initPayload, as: UTF8.self)) { initCString in
      withDuplicatedCString(String(decoding: setupPayload, as: UTF8.self)) { setupCString in
        quickSetup(opaque, initCString, setupCString)
      }
    }
    guard signal.wait(timeout: .now() + 30) == .success else {
      throw TunnelError.coreFailure("mihomo 配置加载超时")
    }
    guard result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TunnelError.coreFailure("mihomo 配置加载失败: \(result)")
    }
  }

  private func applyNetworkSettings(_ provider: PacketTunnelProvider) throws {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    settings.mtu = 9000
    let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4
    settings.dnsSettings = NEDNSSettings(servers: ["172.19.0.2"])

    let signal = DispatchSemaphore(value: 0)
    var failure: Error?
    provider.setTunnelNetworkSettings(settings) { error in failure = error; signal.signal() }
    guard signal.wait(timeout: .now() + 15) == .success else {
      throw TunnelError.coreFailure("系统隧道路由设置超时")
    }
    if let failure { throw failure }
  }
}

private final class CoreCallback {
  weak var provider: PacketTunnelProvider?
  let result: ((String) -> Void)?

  init(provider: PacketTunnelProvider) {
    self.provider = provider
    result = nil
  }

  init(result: @escaping (String) -> Void) {
    provider = nil
    self.result = result
  }
}

private enum CoreCallbacks {
  private static var installed = false
  private static let lock = NSLock()

  static func install() {
    lock.lock()
    defer { lock.unlock() }
    guard !installed else { return }
    hx_install_bridge()
    installed = true
  }
}

@_cdecl("hx_release_object")
func hxReleaseObject(_ object: UnsafeMutableRawPointer?) {
  guard let object else { return }
  Unmanaged<CoreCallback>.fromOpaque(object).release()
}

@_cdecl("hx_free_string")
func hxFreeString(_ value: UnsafeMutablePointer<CChar>?) { free(value) }

@_cdecl("hx_protect")
func hxProtect(_ object: UnsafeMutableRawPointer?, _ descriptor: Int32) {
  // NetworkExtension provider traffic is created outside the packet tunnel by
  // the system; no Android-style VpnService.protect call is required on iOS.
  _ = object
  _ = descriptor
}

@_cdecl("hx_resolve_process")
func hxResolveProcess(
  _ object: UnsafeMutableRawPointer?,
  _ protocolNumber: Int32,
  _ source: UnsafePointer<CChar>?,
  _ target: UnsafePointer<CChar>?,
  _ uid: Int32
) -> UnsafeMutablePointer<CChar>? {
  _ = object; _ = protocolNumber; _ = source; _ = target; _ = uid
  return strdup("")
}

@_cdecl("hx_result")
func hxResult(_ object: UnsafeMutableRawPointer?, _ value: UnsafePointer<CChar>?) {
  guard let object else { return }
  let callback = Unmanaged<CoreCallback>.fromOpaque(object).takeRetainedValue()
  callback.result?(value.map(String.init(cString:)) ?? "")
}

private enum TunnelFileDescriptor {
  static func resolve() throws -> Int32 {
    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
    for descriptor in Int32(0)...Int32(1024) {
      var length = socklen_t(name.count)
      if getsockopt(descriptor, 2, 2, &name, &length) == 0,
         String(cString: name).hasPrefix("utun") {
        return descriptor
      }
    }
    throw TunnelError.tunnelFileDescriptorUnavailable
  }
}

private func withDuplicatedCString<T>(
  _ value: String,
  body: (UnsafeMutablePointer<CChar>) throws -> T
) rethrows -> T {
  let pointer = strdup(value)!
  // FlClash takes ownership and releases the pointer through free_string_func.
  return try body(pointer)
}

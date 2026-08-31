import NetworkExtension

/// Packet Tunnel Extension owns the native mihomo lifecycle. Flutter may be
/// suspended or terminated after the system has started this provider.
final class PacketTunnelProvider: NEPacketTunnelProvider {
  private var runtime: MihomoCoreAdapter?

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    do {
      let profile = try TunnelProfileVerifier().loadAndVerify(
        protocolConfiguration,
        bundle: .main)
      let runtime = try MihomoCoreAdapter(profile: profile, provider: self)
      self.runtime = runtime
      try runtime.start()
      completionHandler(nil)
    } catch {
      runtime?.stop()
      runtime = nil
      completionHandler(error)
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    runtime?.stop()
    runtime = nil
    completionHandler()
  }

  override func sleep(completionHandler: @escaping () -> Void) {
    runtime?.setSuspended(true)
    completionHandler()
  }

  override func wake() { runtime?.setSuspended(false) }
}

package com.hexing.zhilian.secure_tunnel

import android.net.VpnService

/**
 * Owns the Android VPN permission boundary. The service deliberately does not
 * establish a TUN interface until a verified native mihomo runtime is bundled.
 */
class SecureTunnelVpnService : VpnService()

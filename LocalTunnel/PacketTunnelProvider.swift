import NetworkExtension

/// Local loopback transport, following the Jitterbug/LocalDevVPN network technique.
/// No remote VPN server, DNS override, default route or Internet forwarding.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let stateQueue = DispatchQueue(label: "io.altpocket.local-tunnel")
    private var running = false
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.7.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.7.0.2"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route(destinationAddress: "10.7.0.1", subnetMask: "255.255.255.255")]
        ipv4.excludedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        setTunnelNetworkSettings(settings) { error in
            guard error == nil else { completionHandler(error); return }
            self.stateQueue.async {
                self.running = true
                self.readNext()
                completionHandler(nil)
            }
        }
    }
    private func readNext() {
        guard running else { return }
        packetFlow.readPackets { packets, families in
            self.stateQueue.async {
                guard self.running else { return }
                var output = [Data]()
                var protocols = [NSNumber]()
                for (packet, family) in zip(packets, families) {
                    guard family.int32Value == AF_INET, packet.count >= 20,
                          packet[0] >> 4 == 4 else { continue }
                    let headerLength = Int(packet[0] & 15) * 4
                    guard headerLength >= 20, packet.count >= headerLength else { continue }
                    // Swap address bytes, not unaligned UInt32 pointers. The IPv4 and
                    // TCP/UDP one's-complement checksums are invariant under this swap.
                    var reflected = packet
                    reflected.replaceSubrange(12..<16, with: packet[16..<20])
                    reflected.replaceSubrange(16..<20, with: packet[12..<16])
                    output.append(reflected); protocols.append(family)
                }
                if !output.isEmpty { self.packetFlow.writePackets(output, withProtocols: protocols) }
                self.readNext()
            }
        }
    }
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stateQueue.async { self.running = false; completionHandler() }
    }
}

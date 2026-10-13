import Foundation
import EmotionalDamage

/// An in-process WireGuard loopback responder, not a general Internet VPN server.
enum PocketWireGuard {
    static private(set) var isRunning = false
    static var statusText: String { return isRunning ? "UDP 已监听；握手与设备连通性未验证" : "未启动" }
    static func start() throws {
        guard !isRunning else { return }
        let result = start_em_proxy(bind_addr: "127.0.0.1:51820")
        guard result == 0 else {
            throw NSError(domain: "AltPocket.WireGuard", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "WireGuard 服务启动失败（\(result)）。端口可能被占用，请稍后重试。"])
        }
        isRunning = true
        PocketRuntime.startIfPaired()
    }
    static func stop() {
        guard isRunning else { return }
        stop_em_proxy()
        isRunning = false
    }
    static func exportConfiguration() throws -> URL {
        // These are upstream public test keys, not personal credentials.
        // The service is strictly bound to loopback; never expose it to a LAN.
        let configuration = """
        [Interface]
        PrivateKey = AIIeeUDvk3NeAFJ9BWCQvPJize/9WZibMnGJ/0rt5k4=
        Address = 10.7.0.10/24
        
        [Peer]
        PublicKey = kHDoekeYhBvfW9a9UQ+UCmpbG423eejTjcjW+DT+JF0=
        AllowedIPs = 10.7.0.1/32
        Endpoint = 127.0.0.1:51820
        PersistentKeepalive = 25
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AltPocket-Local-WireGuard.conf")
        try Data(configuration.utf8).write(to: url, options: .atomic)
        return url
    }
}

import Foundation
import NetworkExtension

final class PocketVPN {
    static let shared = PocketVPN()
    private(set) var manager: NETunnelProviderManager?
    var status: NEVPNStatus { return manager?.connection.status ?? .invalid }
    private var providerID: String? {
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil),
              let url = urls.first(where: { $0.lastPathComponent == "LocalTunnel.appex" }) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
    func load(_ completion: @escaping (Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            DispatchQueue.main.async {
                self.manager = managers?.first(where: {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.providerID
                })
                completion(error)
            }
        }
    }
    func install(_ completion: @escaping (Error?) -> Void) {
        guard let id = providerID else {
            completion(NSError(domain: "AltPocket", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到内置 VPN 扩展。重签时必须保留 LocalTunnel.appex。"])); return
        }
        load { error in
            if let error = error { completion(error); return }
            let manager = self.manager ?? NETunnelProviderManager()
            let config = NETunnelProviderProtocol()
            config.providerBundleIdentifier = id
            config.serverAddress = "On-device loopback"
            config.disconnectOnSleep = false
            manager.protocolConfiguration = config
            manager.localizedDescription = "AltPocket LocalVPN"
            manager.isEnabled = true
            manager.saveToPreferences { error in
                if let error = error { DispatchQueue.main.async { completion(error) }; return }
                manager.loadFromPreferences { error in
                    DispatchQueue.main.async { self.manager = manager; completion(error) }
                }
            }
        }
    }
    func connect() throws {
        guard let manager = manager, manager.isEnabled else {
            throw NSError(domain: "AltPocket", code: 3, userInfo: [NSLocalizedDescriptionKey: "请先安装 VPN 配置。"])
        }
        try manager.connection.startVPNTunnel()
    }
    func disconnect() { manager?.connection.stopVPNTunnel() }
    var statusText: String {
        switch status {
        case .connected: return "已连接"
        case .connecting: return "正在连接"
        case .disconnecting: return "正在断开"
        case .reasserting: return "正在重连"
        case .disconnected: return "未连接"
        case .invalid: return "尚未配置"
        @unknown default: return "未知状态"
        }
    }
}

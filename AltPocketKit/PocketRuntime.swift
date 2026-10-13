import Foundation
import minimuxer

/// Device secrets remain in the app container and are never included in CI artifacts.
enum PocketRuntime {
    static var pairingURL: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ALTPairingFile.mobiledevicepairing")
    }
    static var hasPairing: Bool { return FileManager.default.fileExists(atPath: pairingURL.path) }
    static var deviceUDID: String? {
        let value = UserDefaults.standard.string(forKey: "PocketDeviceUDID")
            ?? (Bundle.main.object(forInfoDictionaryKey: "ALTDeviceID") as? String)
        guard let id = value, !id.isEmpty else { return nil }
        return id
    }
    private static var started = false
    private static var didAttemptStart = false
    static private(set) var lastError: String?
    static func startIfPaired() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { startIfPaired() }
            return
        }
        guard !didAttemptStart, let udid = deviceUDID,
              let data = try? Data(contentsOf: pairingURL),
              var pairing = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return }
        if let original = pairing["UDID"] as? String, original.caseInsensitiveCompare(udid) != .orderedSame {
            lastError = "配对文件中的 UDID 与设置不一致，请检查是否为同一台设备。"
            return
        }
        pairing["UDID"] = udid
        guard let normalized = try? PropertyListSerialization.data(fromPropertyList: pairing, format: .xml, options: 0),
              let xml = String(data: normalized, encoding: .utf8) else { return }
        // The legacy library has a process-global logger; retry requires relaunch.
        didAttemptStart = true
        set_usbmuxd_socket()
        let result = start_minimuxer(pairing_file: xml)
        if result == 0 { started = true; lastError = nil }
        else { lastError = "设备连接核心启动失败（\(result)）。请检查配对文件并重新打开 App。" }
    }
    static func importPairing(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count < 2_000_000,
              let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              dict["HostID"] is String, dict["SystemBUID"] is String,
              dict["HostCertificate"] is Data, dict["HostPrivateKey"] is Data,
              dict["RootCertificate"] is Data, dict["RootPrivateKey"] is Data else {
            throw NSError(domain: "AltPocket", code: 1, userInfo: [NSLocalizedDescriptionKey: "不是有效的设备配对文件。请从已信任的电脑导出本机 pairing plist。"])
        }
        let xml = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try xml.write(to: pairingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var saved = pairingURL
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try saved.setResourceValues(values)
        let candidate = (dict["UDID"] as? String) ?? url.deletingPathExtension().lastPathComponent
        if validUDID(candidate) { UserDefaults.standard.set(candidate, forKey: "PocketDeviceUDID") }
        startIfPaired()
    }
    static func validUDID(_ value: String) -> Bool {
        return value.range(of: "^(?:[0-9A-Fa-f]{40}|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})$", options: .regularExpression) != nil
    }
}

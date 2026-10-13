import UIKit
import Network
import NetworkExtension

final class PocketSetupController: UITableViewController, UIDocumentPickerDelegate {
    private var busy = false
    private var probe: NWConnection?
    private var probeTimeout: DispatchWorkItem?
    init() { super.init(style: .grouped) }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AltPocket · 本机服务"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 66
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .NEVPNStatusDidChange, object: nil)
        PocketVPN.shared.load { [weak self] error in
            self?.tableView.reloadData()
            if let error = error { self?.show(error.localizedDescription) }
        }
    }
    deinit { NotificationCenter.default.removeObserver(self); probe?.cancel(); probeTimeout?.cancel() }
    @objc private func refresh() { DispatchQueue.main.async { self.tableView.reloadData() } }
    override func numberOfSections(in tableView: UITableView) -> Int { return 3 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return [3, 4, 1][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return ["1 · 设备与签名准备", "2 · 内置 LocalVPN", "3 · 实验版说明"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "从已信任的电脑导出本机配对文件。UDID 可在电脑设备信息中查看。Anisette 服务只接收数据请求；Apple ID 密码由签名核心发给 Apple。请仅使用自己信任的 HTTPS 服务。" }
        if section == 1 { return "状态：\(PocketVPN.shared.statusText)。\(PocketRuntime.lastError ?? "")主 App 和扩展都需要带 Network Extension 权限的有效签名。普通免费 Apple ID 无法签发此权限。只处理本机 10.7.0.1 的流量，不提供上网代理。" }
        return "基于 SideStore 0.1.1 / AltStore，AGPL-3.0；独立实验分支，非官方产品。iOS 12 真机、Apple 登录与续签尚待验证；新 iOS 也不保证兼容。后台续签由系统调度，不能保证常驻。"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        let titles = [["导入配对文件", "设置本机 UDID", "设置 Anisette HTTPS 地址"], ["安装 VPN 配置", "连接 LocalVPN", "断开 LocalVPN", "检测设备服务"], ["使用方法与开源说明"]]
        cell.textLabel?.text = titles[indexPath.section][indexPath.row]
        if indexPath.section == 0 {
            cell.detailTextLabel?.text = [PocketRuntime.hasPairing ? "已导入；更换后请重新打开 App" : "尚未导入", PocketRuntime.deviceUDID == nil ? "尚未设置" : "已设置（不显示完整设备标识）", UserDefaults.standard.customAnisetteURL == nil ? "必须设置；无默认第三方服务" : "已设置"][indexPath.row]
        }
        cell.isUserInteractionEnabled = !busy
        if #available(iOS 13, *) { cell.textLabel?.textColor = .label }
        else { cell.textLabel?.textColor = .darkText }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy else { return }
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                let picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.xml"], in: .import)
                picker.delegate = self
                present(picker, animated: true)
            case 1:
                input(title: "本机 UDID", value: PocketRuntime.deviceUDID) { value in
                    guard PocketRuntime.validUDID(value) else { self.show("UDID 格式不正确，请完整复制电脑显示的设备标识。"); return }
                    UserDefaults.standard.set(value, forKey: "PocketDeviceUDID")
                    PocketRuntime.startIfPaired()
                    self.tableView.reloadData()
                }
            default:
                input(title: "Anisette HTTPS 地址", value: UserDefaults.standard.customAnisetteURL) { value in
                    guard let url = URL(string: value), url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else { self.show("请输入有效的 HTTPS 地址，不能在地址中嵌入账号或密码。"); return }
                    UserDefaults.standard.customAnisetteURL = value
                    self.tableView.reloadData()
                }
            }
        } else if indexPath.section == 1 {
            switch indexPath.row {
            case 0:
                busy = true; tableView.reloadData()
                PocketVPN.shared.install { [weak self] error in
                    guard let self = self else { return }
                    self.busy = false; self.tableView.reloadData()
                    self.show(error.map { "VPN 配置失败：\($0.localizedDescription)\n请检查 App 和扩展的签名权限。" } ?? "VPN 配置已安装，可以连接。")
                }
            case 1:
                do { try PocketVPN.shared.connect(); PocketRuntime.startIfPaired() }
                catch { show(error.localizedDescription) }
            case 2: PocketVPN.shared.disconnect()
            default: testDevice()
            }
        } else {
            show("先签名安装 AltPocket（保留扩展及 VPN 权限），再导入本机配对文件、设置 UDID 与可信 Anisette 地址，连接 LocalVPN。最后在 Settings 登录 Apple ID，在 My Apps 的 + 导入 IPA。\n\n连接检测只证明 TCP 端口可达，不代表配对、签名或安装成功。此版本不依赖持续运行的电脑，但首次安装/配对需要电脑。\n\n来源：SideStore/SideStore、altstoreio/AltStore；本地回环方案参考 osy/Jitterbug 与 jkcoxson/LocalDevVPN。\n源码：https://github.com/errormoonlight1225/AltPocket")
        }
    }
    private func input(title: String, value: String?, save: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.text = value; field.autocapitalizationType = .none; field.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            save(alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        })
        present(alert, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do { try PocketRuntime.importPairing(from: url); tableView.reloadData(); show("配对文件已导入。若更换了文件，请退出并重新打开 App。") }
        catch { show(error.localizedDescription) }
    }
    private func testDevice() {
        guard PocketVPN.shared.status == .connected else { show("请先连接内置 LocalVPN。"); return }
        busy = true; tableView.reloadData()
        let connection = NWConnection(host: "10.7.0.1", port: 62078, using: .tcp)
        probe = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.endProbe("TCP 62078 可达。接下来可测试 Apple ID 登录和 IPA 安装；配对尚未由此检测验证。")
            case .failed(let error): self?.endProbe("设备连接失败：\(error.localizedDescription)")
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.endProbe("连接超时。请解锁设备、检查 VPN 权限与系统兼容性。") }
        probeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
        connection.start(queue: .main)
    }
    private func endProbe(_ message: String) {
        guard probe != nil else { return }
        probe?.stateUpdateHandler = nil; probe?.cancel(); probe = nil
        probeTimeout?.cancel(); probeTimeout = nil
        busy = false; tableView.reloadData(); show(message)
    }
    private func show(_ message: String) {
        let alert = UIAlertController(title: "AltPocket", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        if let presented = presentedViewController {
            presented.dismiss(animated: true) { self.present(alert, animated: true) }
        } else { present(alert, animated: true) }
    }
}

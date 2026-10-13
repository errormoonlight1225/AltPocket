# AltPocket — iOS 12 compatibility experiment

独立开源实验分支，基于 **SideStore 0.1.1**（`c9001f068bd03b3ff3748f7f24d8f22e64057d27`）及 AltStore，目标是在 iPhone / iPad 本机签名、安装和刷新 IPA，并内置 LocalVPN。**不是 AltStore / SideStore 官方版本。**

## 当前状态

- 已通过 Xcode 15.4 编译；主 App、内置 VPN 扩展的 plist 和 Mach-O 最低版本均验证为 iOS 12.0（arm64）。
- **尚未经过 iOS 12 真机验证**；不能把构建成功视为登录、配对、安装或续签成功。
- 签名、证书、IPA 重签、安装流程继承旧版 AltSign / SideStore / minimuxer。旧版 Apple 登录与 anisette 协议是否仍被 Apple 接受，需要实测；不声称支持所有新 iOS。
- 新增原生 UIKit 本机服务页面、嵌入式 Packet Tunnel 扩展、VPN 管理、TCP 端口检测、安全配对文件导入。
- 禁用上游 AppCenter 遥测；移除上游的固定设备 ID、默认 anisette 地址；修复 anisette 错误路径不结束/强制解包崩溃。
- 不提供后台常驻保证；iOS 决定后台刷新时机。

## 签名要求（请先读）

Actions 生成的是 **未签名 IPA**。内置 VPN 主程序和 LocalTunnel.appex 均需包含有效的 `com.apple.developer.networking.networkextension = packet-tunnel-provider` 权限与匹配的 provisioning profiles。普通免费 Apple ID 不提供该权限；改 plist 或假签无法赋予权限。一般需由具备相应能力的付费开发者账号签名，且签名工具必须保留扩展。证书类型本身不能代替正确权限。

首次安装、信任与生成设备配对文件仍需电脑。此项目不绕过设备信任，也不会凭空生成配对密钥。AltPocket 与官方 SideStore 使用不同应用/数据组标识，官方源仅用于浏览其他 App；本分支升级请下载新的 IPA 手动安装。

## 使用

1. 用具备 Network Extension 权限的有效签名安装整个 IPA，保留 VPN 扩展。
2. 打开 LocalVPN 页，导入本机 `.mobiledevicepairing` / pairing `.plist` 文件。支持二进制与 XML plist；配对文件只在本地保存并排除备份。
3. 设置**本机** UDID；从电脑设备信息取得，不要公开上传。
4. 设置自己信任的 HTTPS anisette 服务。没有默认第三方服务；此核心使用旧式 JSON anisette 响应，不保证任意新服务兼容。
5. 安装 VPN 配置并允许系统提示，连接 LocalVPN。只路由 `10.7.0.1/32`，不是上网 VPN。
6. 设备保持解锁；“检测设备服务”只测 TCP 62078 可达性，不验证配对、签名或安装。
7. Settings 登录 Apple ID，My Apps → `+` 导入 IPA，点击应用剩余天数刷新。更换配对文件后重新打开 App。

Apple ID 认证流程由上游 AltSign 对接 Apple。不要把密码、证书、配对文件、anisette 身份数据或 UDID 放进仓库、Actions 日志或 issue。请自行审查依赖后使用实验签名工具。

## 构建

GitHub Actions → **Build AltPocket iOS 12** → **Run workflow**。工作流使用 macOS 14 / Xcode 15.4，构建 app 与 VPN，验证两者的最低系统版本，上传 unsigned IPA、SHA-256 构建报告和含 Git 子模块的源码快照（Swift / Rust 包按锁定信息获取）。构建日志单独上传。

本地需 macOS、Xcode 15.4、Ruby / xcodeproj、Rust / iOS target：

```sh
git clone --recursive https://github.com/errormoonlight1225/AltPocket.git
cd AltPocket
gem install xcodeproj
ruby scripts/configure.rb
rustup target add aarch64-apple-ios
export IPHONEOS_DEPLOYMENT_TARGET=12.0
cargo build --locked --manifest-path Dependencies/em_proxy/Cargo.toml --release --lib --target aarch64-apple-ios
cargo build --locked --manifest-path Dependencies/minimuxer/Cargo.toml --release --lib --target aarch64-apple-ios
xcodebuild -project AltStore.xcodeproj -scheme AltStore -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -archivePath build/AltPocket.xcarchive archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
python3 scripts/package.py
```

## 来源与许可证

- SideStore: https://github.com/SideStore/SideStore
- AltStore / Riley Testut: https://github.com/altstoreio/AltStore
- 原有子模块和 Swift 包保留其许可证及版权。
- 本机回环网络技术参考 Jitterbug（https://github.com/osy/Jitterbug）和 LocalDevVPN（https://github.com/jkcoxson/LocalDevVPN）；这里是独立编写的 Packet Tunnel 实现，未使用 LocalDevVPN 品牌与图标。
- `Vendor/num_threads-0.1.7` 保留 Jacob Pratt 的 MIT 许可证；Darwin 兼容修改只替换失效的 task-port 包装接口。
- 本项目衍生代码遵循上游 **AGPL-3.0**，参见 LICENSE。保留 Git 历史及原作者署名。新增兼容与 VPN 代码由 AI 辅助编写，需人工与真机审查；不向上游提交自动化 PR。


## 0.1.1：实验性 WireGuard 本地服务

本机服务页面新增启动/停止 WireGuard UDP 服务、导出 `.conf` 与 TCP 设备检测。复用固定版本 em_proxy / BoringTun，真正进行 WireGuard 握手、解密、IPv4 地址交换与重新加密，不是界面占位功能。

1. 断开内置 LocalVPN。
2. 导出客户端配置，在**另一个兼容系统版本的 WireGuard 客户端**导入。
3. 回到 AltPocket 启动服务，再到客户端开启隧道，返回 AltPocket 检测设备服务。
4. 检测只验证 TCP 62078 可达，不证明配对、登录、安装或续签成功。

仅绑定 `127.0.0.1:51820`，仅路由 `10.7.0.1/32`，不修改 DNS，不提供远程上网代理。配置沿用上游公开测试密钥，**不可用于真实远程 VPN 或暴露到局域网**。

服务运行在 App 进程，切换客户端或后台后可能被 iOS 暂停。UDP 监听状态不是握手成功状态。iOS 12 真机尚未验证；当前没有确认可直接下载的 iOS 12 WireGuard 客户端。本次保留内置 LocalVPN 扩展，因此此 IPA 的签名权限要求不变，不能宣称已支持免费 Apple ID 安装。

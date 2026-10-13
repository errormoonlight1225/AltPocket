// Based on SideStore / AltStore. Preserve asynchronous operation completion on every path.
import Foundation
import AltStoreCore
import AltSign
import Roxas

@objc(FetchAnisetteDataOperation)
class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData> {
    let context: OperationContext
    init(context: OperationContext) { self.context = context }
    override func main() {
        super.main()
        if let error = context.error { finish(.failure(error)); return }
        let url = AnisetteManager.currentURL
        guard url.scheme == "https", url.host != "anisette.invalid", url.host != nil else {
            finish(.failure(Self.failure("请先在 LocalVPN 页面设置可信的 Anisette HTTPS 服务地址。"))); return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { self.finish(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let data = data else {
                self.finish(.failure(Self.failure("Anisette 服务未返回有效响应。"))); return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String] else { throw Self.failure("Anisette 响应格式不正确。") }
                let mapping = ["machineID": "X-Apple-I-MD-M", "oneTimePassword": "X-Apple-I-MD", "localUserID": "X-Apple-I-MD-LU", "routingInfo": "X-Apple-I-MD-RINFO", "deviceUniqueIdentifier": "X-Mme-Device-Id", "deviceDescription": "X-MMe-Client-Info", "date": "X-Apple-I-Client-Time", "locale": "X-Apple-Locale", "timeZone": "X-Apple-I-TimeZone"]
                var formatted = ["deviceSerialNumber": "1"]
                for (destination, source) in mapping {
                    guard let value = json[source], !value.isEmpty else { throw Self.failure("Anisette 响应缺少必要字段：\(source)。此版本需要兼容旧版 AltSign 的响应。") }
                    formatted[destination] = value
                }
                guard let anisette = ALTAnisetteData(json: formatted) else { throw Self.failure("无法解析 Anisette 数据。") }
                self.finish(.success(anisette))
            } catch { self.finish(.failure(error)) }
        }.resume()
    }
    private static func failure(_ text: String) -> NSError {
        return NSError(domain: "AltPocket.Anisette", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}

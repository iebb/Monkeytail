import Foundation

public struct WatchResponse: Sendable {
    public var status: Int
    public var duration: Double
    public var headers: [String: String]
    public var body: Data
    public var url: String
    public var text: String { String(data: body.prefix(16 * 1024), encoding: .utf8) ?? "Binary response — use Hex." }
    public var pretty: String {
        guard body.count <= 16 * 1024, let value = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]), let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys]), data.count <= 32 * 1024 else { return text }
        return String(decoding: data, as: UTF8.self)
    }
    public var hex: String { body.prefix(16 * 1024).enumerated().reduce(into: "") { result, item in
        if item.offset % 8 == 0 { result += String(format: "%08X  ", item.offset) }
        result += String(format: "%02X", item.element) + (item.offset % 8 == 7 ? "\n" : " ")
    } }
}
public final class WatchHTTPClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let model: WatchRequest
    public init(_ model: WatchRequest) { self.model = model }
    public func send() async throws -> WatchResponse {
        let request = try model.request()
        let config = URLSessionConfiguration.ephemeral; config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData; config.timeoutIntervalForRequest = model.timeout; config.timeoutIntervalForResource = model.timeout
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil); defer { session.invalidateAndCancel() }
        let start = ContinuousClock.now
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw WatchError("The server did not return an HTTP response.") }
        guard response.expectedContentLength <= 256 * 1024 else { throw WatchError("Watch responses are limited to 256 KB.") }
        var data = Data()
        for try await byte in bytes { guard data.count < 256 * 1024 else { throw WatchError("Watch responses are limited to 256 KB.") }; data.append(byte) }
        try Task.checkCancellation()
        let duration = start.duration(to: .now).components
        return WatchResponse(status: http.statusCode, duration: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
            headers: http.allHeaderFields.reduce(into: [:]) { $0[String(describing: $1.key)] = String(describing: $1.value) }, body: data, url: http.url?.absoluteString ?? model.url)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard model.followRedirects, let target = request.url, ["http", "https"].contains(target.scheme?.lowercased() ?? ""), target.host != nil, target.user == nil, target.password == nil else { completionHandler(nil); return }
        func origin(_ url: URL?) -> String { guard let url else { return "" }; return "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme == "https" ? 443 : 80))" }
        var redirected = request
        if origin(task.currentRequest?.url ?? task.originalRequest?.url) != origin(target) {
            for header in (request.allHTTPHeaderFields ?? [:]).keys {
                let key = header.lowercased()
                if ["authorization", "proxy-authorization", "cookie", "x-api-key", "x-amz-security-token"].contains(key) || model.sensitiveHeaders.contains(where: { $0.caseInsensitiveCompare(header) == .orderedSame }) { redirected.setValue(nil, forHTTPHeaderField: header) }
            }
        }
        completionHandler(redirected)
    }
}

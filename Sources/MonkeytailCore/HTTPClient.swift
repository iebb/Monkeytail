import Foundation
import Network

public final class HTTPClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let followRedirects: Bool
    public init(followRedirects: Bool = true) { self.followRedirects = followRedirects }

    public static func configuration(proxy: ProxySettings, timeout: Double) throws -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        if proxy.kind != .system {
            guard !proxy.host.trimmingCharacters(in: .whitespaces).isEmpty,
                  !proxy.host.contains("://"), let rawPort = UInt16(proxy.port), rawPort > 0,
                  let port = NWEndpoint.Port(rawValue: rawPort) else { throw ClientError("Enter a proxy hostname and port between 1 and 65535.") }
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: port)
            var setting = proxy.kind == .socks ? ProxyConfiguration(socksv5Proxy: endpoint) : ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: proxy.kind == .https ? NWProtocolTLS.Options() : nil)
            setting.allowFailover = false
            if !proxy.username.isEmpty { setting.applyCredential(username: proxy.username, password: proxy.password) }
            configuration.proxyConfigurations = [setting]
        }
        return configuration
    }

    public func send(_ request: URLRequest, proxy: ProxySettings = ProxySettings()) async throws -> APIResponse {
        let session = URLSession(configuration: try Self.configuration(proxy: proxy, timeout: request.timeoutInterval), delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let started = ContinuousClock.now
        // Stream into a bounded buffer so an accidental download cannot exhaust phone memory.
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError("The server did not return an HTTP response.") }
        let maximum = 20 * 1024 * 1024
        if response.expectedContentLength > maximum { throw ClientError("The response exceeds the 20 MB limit.") }
        var body = Data()
        for try await byte in bytes {
            if body.count >= maximum { throw ClientError("The response exceeds the 20 MB limit.") }
            body.append(byte)
        }
        try Task.checkCancellation()
        let elapsed = started.duration(to: .now).components
        let duration = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let headers = http.allHeaderFields.map { Field(String(describing: $0.key), String(describing: $0.value)) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return APIResponse(status: http.statusCode, headers: headers, body: body, duration: duration, url: http.url?.absoluteString ?? request.url!.absoluteString)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard followRedirects else { completionHandler(nil); return }
        var next = request
        if let previous = task.currentRequest?.url, let target = request.url,
           previous.host != target.host || previous.port != target.port || previous.scheme != target.scheme {
            for header in ["Authorization", "Cookie", "Proxy-Authorization"] { next.setValue(nil, forHTTPHeaderField: header) }
        }
        completionHandler(next)
    }
}

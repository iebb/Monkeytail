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

    public func send(_ request: URLRequest, proxy: ProxySettings = ProxySettings(), impersonation: BrowserImpersonation? = nil) async throws -> APIResponse {
        if let impersonation {
            return try await BrowserHTTPClient(followRedirects: followRedirects).send(request, proxy: proxy, impersonation: impersonation)
        }
        let trace = SessionTrace(followRedirects: followRedirects, original: request)
        let session = URLSession(configuration: try Self.configuration(proxy: proxy, timeout: request.timeoutInterval), delegate: trace, delegateQueue: nil)
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
        var result = APIResponse(status: http.statusCode, headers: headers, body: body, duration: duration, url: http.url?.absoluteString ?? request.url!.absoluteString)
        result.diagnostics = RequestDiagnostics(transport: "System", transactions: await trace.transactions())
        return result
    }

}

private final class SessionTrace: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let followRedirects: Bool
    private let original: URLRequest
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var captured: [HTTPTransaction]?
    private var pending: CheckedContinuation<[HTTPTransaction], Never>?
    init(followRedirects: Bool, original: URLRequest) { self.followRedirects = followRedirects; self.original = original; requests = [original] }
    func transactions() async -> [HTTPTransaction] {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let captured { lock.unlock(); continuation.resume(returning: captured) }
            else { pending = continuation; lock.unlock() }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        func interval(_ start: Date?, _ end: Date?) -> Double? {
            guard let start, let end else { return nil }; return max(0, end.timeIntervalSince(start))
        }
        lock.lock(); let sent = requests; lock.unlock()
        let transactions = metrics.transactionMetrics.map { item in
            var request = item.request
            // Metrics may omit the body; carry it only if method and URL still match this transaction.
            if request.httpBody == nil, let recorded = sent.last(where: { $0.url == request.url && $0.httpMethod == request.httpMethod }) { request.httpBody = recorded.httpBody }
            return HTTPTransaction(request: SentRequest(request), status: (item.response as? HTTPURLResponse)?.statusCode ?? 0,
                dns: interval(item.domainLookupStartDate, item.domainLookupEndDate),
                connect: interval(item.connectStartDate, item.secureConnectionStartDate ?? item.connectEndDate),
                tls: interval(item.secureConnectionStartDate, item.secureConnectionEndDate),
                upload: interval(item.requestStartDate, item.requestEndDate), wait: interval(item.requestEndDate, item.responseStartDate),
                download: interval(item.responseStartDate, item.responseEndDate), total: interval(item.fetchStartDate, item.responseEndDate),
                protocolName: item.networkProtocolName, remoteAddress: item.remoteAddress, proxy: item.isProxyConnection, reusedConnection: item.isReusedConnection)
        }
        finish(transactions)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish([]) }
    private func finish(_ result: [HTTPTransaction]) {
        lock.lock()
        if captured == nil { captured = result }
        let waiter = pending; pending = nil; let value = captured ?? []
        lock.unlock(); waiter?.resume(returning: value)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard followRedirects else { completionHandler(nil); return }
        var next = request
        if let previous = task.currentRequest?.url, let target = request.url,
           previous.host != target.host || previous.port != target.port || previous.scheme != target.scheme {
            for header in ["Authorization", "Cookie", "Proxy-Authorization"] { next.setValue(nil, forHTTPHeaderField: header) }
        }
        lock.lock(); requests.append(next); lock.unlock()
        completionHandler(next)
    }
}

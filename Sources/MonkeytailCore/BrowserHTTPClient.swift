import Foundation
import CFNetwork
import MonkeytailCurl

/// Runs the pinned browser TLS/HTTP2 stack locally; no relay or helper service.
final class BrowserHTTPClient: @unchecked Sendable {
    private static let initialized = curl_global_init(Int(CURL_GLOBAL_DEFAULT))
    private let followRedirects: Bool
    // An explicit root bundle is used only by local transport tests.
    private let certificateAuthorities: Data?
    init(followRedirects: Bool = true, certificateAuthorities: Data? = nil) {
        self.followRedirects = followRedirects; self.certificateAuthorities = certificateAuthorities
    }

    func send(_ request: URLRequest, proxy: ProxySettings, impersonation: BrowserImpersonation) async throws -> APIResponse {
        let cancellation = CurlCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try self.perform(request, proxy: proxy, impersonation: impersonation, cancellation: cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    private func perform(_ original: URLRequest, proxy: ProxySettings, impersonation: BrowserImpersonation, cancellation: CurlCancellation) throws -> APIResponse {
        try check(Self.initialized)
        let started = ContinuousClock.now
        var request = original
        var transactions: [HTTPTransaction] = []
        for hop in 0...10 {
            if cancellation.isCancelled { throw CancellationError() }
            let elapsed = seconds(started.duration(to: .now))
            let remaining = original.timeoutInterval - elapsed
            guard remaining > 0 else { throw URLError(.timedOut) }
            request.timeoutInterval = remaining
            var response = try transfer(request, proxy: proxy, impersonation: impersonation, cancellation: cancellation)
            transactions += response.diagnostics?.transactions ?? []
            response.diagnostics = RequestDiagnostics(transport: impersonation.profile.title, transactions: transactions)
            response.duration = seconds(started.duration(to: .now))
            guard followRedirects, [301, 302, 303, 307, 308].contains(response.status),
                  let location = response.headers.first(where: { $0.name.lowercased() == "location" })?.value,
                  let current = request.url else { return response }
            guard hop < 10 else { throw ClientError("Too many redirects (maximum 10).") }
            guard let target = URL(string: location, relativeTo: current)?.absoluteURL,
                  ["http", "https"].contains(target.scheme?.lowercased() ?? ""), target.host != nil,
                  target.user == nil, target.password == nil else { throw ClientError("Unsupported redirect URL.") }
            if origin(current) != origin(target) {
                for header in ["Authorization", "Cookie", "Proxy-Authorization"] { request.setValue(nil, forHTTPHeaderField: header) }
            }
            // Host is regenerated for the redirect target, as it is in URLSession.
            request.setValue(nil, forHTTPHeaderField: "Host")
            let method = request.httpMethod ?? "GET"
            if (response.status == 303 && method != "HEAD") || ([301, 302].contains(response.status) && method == "POST") {
                request.httpMethod = "GET"; request.httpBody = nil
                for header in ["Content-Type", "Content-Length", "Transfer-Encoding"] { request.setValue(nil, forHTTPHeaderField: header) }
            }
            request.url = target
        }
        throw ClientError("Too many redirects.")
    }

    private func transfer(_ request: URLRequest, proxy: ProxySettings, impersonation: BrowserImpersonation, cancellation: CurlCancellation) throws -> APIResponse {
        guard let url = request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { throw ClientError("Use an HTTP or HTTPS URL without embedded credentials.") }
        guard let curl = curl_easy_init() else { throw ClientError("Unable to initialize browser transport.") }
        defer { curl_easy_cleanup(curl) }
        func long(_ option: CURLoption, _ value: Int) throws { try check(mt_curl_long(curl, option, value)) }
        func string(_ option: CURLoption, _ value: String) throws {
            guard !value.contains("\0") else { throw ClientError("Request values cannot contain a null character.") }
            try check(mt_curl_string(curl, option, value))
        }
        try check(curl_easy_impersonate(curl, impersonation.profile.rawValue, impersonation.browserHeaders ? 1 : 0))
        try string(CURLOPT_URL, url.absoluteString)
        try string(CURLOPT_PROTOCOLS_STR, "http,https")
        try long(CURLOPT_FOLLOWLOCATION, 0)
        try long(CURLOPT_NOSIGNAL, 1)
        try long(CURLOPT_TIMEOUT_MS, max(1, Int(request.timeoutInterval * 1000)))
        try long(CURLOPT_SSL_VERIFYPEER, 1)
        try long(CURLOPT_SSL_VERIFYHOST, 2)
        try long(CURLOPT_PROXY_SSL_VERIFYPEER, 1)
        try long(CURLOPT_PROXY_SSL_VERIFYHOST, 2)
        try long(CURLOPT_PROXY_SSL_OPTIONS, Int(CURLSSLOPT_NATIVE_CA))
        if let certificateAuthorities {
            try long(CURLOPT_SSL_OPTIONS, 0)
            try certificateAuthorities.withUnsafeBytes { try check(mt_curl_ca(curl, $0.baseAddress, $0.count)) }
        } else { try long(CURLOPT_SSL_OPTIONS, Int(CURLSSLOPT_NATIVE_CA)) }
        // Decode compressed responses before enforcing the preview/memory bound.
        try string(CURLOPT_ACCEPT_ENCODING, request.value(forHTTPHeaderField: "Accept-Encoding") ?? "")
        let selectedProxy = try resolvedProxy(proxy, for: url)
        if selectedProxy.kind == .system {
            try string(CURLOPT_PROXY, "") // Do not inherit process environment proxies.
        } else {
            _ = try HTTPClient.configuration(proxy: selectedProxy, timeout: request.timeoutInterval)
            let proxyHost = selectedProxy.host.contains(":") && !selectedProxy.host.hasPrefix("[") ? "[\(selectedProxy.host)]" : selectedProxy.host
            try string(CURLOPT_PROXY, proxyHost)
            try long(CURLOPT_PROXYPORT, Int(selectedProxy.port)!)
            let kind = selectedProxy.kind == .socks ? CURLPROXY_SOCKS5_HOSTNAME : selectedProxy.kind == .https ? CURLPROXY_HTTPS : CURLPROXY_HTTP
            try long(CURLOPT_PROXYTYPE, kind)
            if selectedProxy.kind != .socks { try long(CURLOPT_HTTPPROXYTUNNEL, 1) }
            try string(CURLOPT_NOPROXY, "") // An explicitly selected proxy never bypasses localhost.
            if !selectedProxy.username.isEmpty {
                try string(CURLOPT_PROXYUSERNAME, selectedProxy.username)
                try string(CURLOPT_PROXYPASSWORD, selectedProxy.password)
            }
        }
        var headers: UnsafeMutablePointer<curl_slist>?
        defer { curl_slist_free_all(headers) }
        for (name, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard !name.contains("\0"), !value.contains("\0"), !value.contains("\r"), !value.contains("\n") else { throw ClientError("Invalid request header.") }
            let line = value.isEmpty ? name + ";" : name + ": " + value
            guard let updated = curl_slist_append(headers, line) else { throw ClientError("Unable to allocate request headers.") }
            headers = updated
        }
        try check(mt_curl_headers(curl, headers))
        let method = request.httpMethod ?? "GET"
        if let body = request.httpBody {
            try body.withUnsafeBytes { try check(mt_curl_body(curl, $0.baseAddress, $0.count)) }
        } else if ["POST", "PUT", "PATCH"].contains(method) { try check(mt_curl_body(curl, nil, 0)) }
        if method == "HEAD" { try long(CURLOPT_NOBODY, 1) }
        try string(CURLOPT_CUSTOMREQUEST, method)
        let state = CurlResponseBuffer(cancellation: cancellation)
        let context = Unmanaged.passUnretained(state).toOpaque()
        try check(mt_curl_callbacks(curl, context, curlBodyCallback, curlHeaderCallback))
        try check(mt_curl_debug(curl, context, curlDebugCallback))
        let result = mt_curl_run(curl, context, curlCancelledCallback)
        if cancellation.isCancelled { throw CancellationError() }
        if let error = state.error { throw error }
        try check(result)
        let effectiveURL = mt_curl_effective_url(curl).map { String(cString: $0) } ?? url.absoluteString
        var response = APIResponse(status: Int(mt_curl_status(curl)), headers: state.headers, body: state.body, duration: 0, url: effectiveURL)
        let dns = mt_curl_time(curl, CURLINFO_NAMELOOKUP_TIME), connect = mt_curl_time(curl, CURLINFO_CONNECT_TIME)
        let tls = mt_curl_time(curl, CURLINFO_APPCONNECT_TIME), ready = mt_curl_time(curl, CURLINFO_PRETRANSFER_TIME)
        let uploadEnd = mt_curl_upload_end(curl)
        let firstByte = mt_curl_time(curl, CURLINFO_STARTTRANSFER_TIME), total = mt_curl_time(curl, CURLINFO_TOTAL_TIME)
        let protocolNumber = mt_curl_info_long(curl, CURLINFO_HTTP_VERSION)
        let protocolName = [Int(CURL_HTTP_VERSION_1_0): "http/1.0", Int(CURL_HTTP_VERSION_1_1): "http/1.1", Int(CURL_HTTP_VERSION_2_0): "h2", Int(CURL_HTTP_VERSION_3): "h3"][protocolNumber]
        let remote = mt_curl_info_string(curl, CURLINFO_PRIMARY_IP).map { String(cString: $0) }
        response.diagnostics = RequestDiagnostics(transport: impersonation.profile.title, transactions: [HTTPTransaction(
            request: SentRequest(request, headers: state.sentHeaders.isEmpty ? nil : state.sentHeaders), status: response.status,
            dns: dns, connect: max(0, connect - dns), tls: tls > 0 ? max(0, tls - connect) : nil,
            upload: uploadEnd > 0 ? max(0, uploadEnd - ready) : nil, wait: uploadEnd > 0 ? max(0, firstByte - uploadEnd) : nil, download: max(0, total - firstByte), total: total,
            protocolName: protocolName, remoteAddress: remote, proxy: selectedProxy.kind != .system,
            reusedConnection: mt_curl_info_long(curl, CURLINFO_NUM_CONNECTS) == 0)])
        return response
    }

    private func resolvedProxy(_ proxy: ProxySettings, for url: URL) throws -> ProxySettings {
        guard proxy.kind == .system else { return proxy }
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue(),
              let first = (CFNetworkCopyProxiesForURL(url as CFURL, settings).takeRetainedValue() as NSArray).firstObject as? [String: Any],
              let type = first[kCFProxyTypeKey as String] as? String else { return ProxySettings() }
        var result = ProxySettings()
        if type == (kCFProxyTypeNone as String) { return result }
        else if type == (kCFProxyTypeHTTP as String) { result.kind = .http }
        else if type == (kCFProxyTypeHTTPS as String) { result.kind = .https }
        else if type == (kCFProxyTypeSOCKS as String) { result.kind = .socks }
        else { throw ClientError("This automatic proxy requires the System TLS profile. Choose an explicit proxy to use a browser profile.") }
        result.host = first[kCFProxyHostNameKey as String] as? String ?? ""
        result.port = (first[kCFProxyPortNumberKey as String] as? NSNumber)?.stringValue ?? ""
        result.username = first[kCFProxyUsernameKey as String] as? String ?? ""
        result.password = first[kCFProxyPasswordKey as String] as? String ?? ""
        return result
    }
    private func origin(_ url: URL) -> String { "\(url.scheme?.lowercased() ?? "")://\(url.host?.lowercased() ?? ""):\(url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80))" }
    private func seconds(_ duration: Duration) -> Double { Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18 }
    private func check(_ result: CURLcode) throws {
        guard result == CURLE_OK else { throw ClientError("Browser transport: \(String(cString: curl_easy_strerror(result)))") }
    }
}

private final class CurlCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
private final class CurlResponseBuffer {
    let cancellation: CurlCancellation
    var body = Data()
    var headers: [Field] = []
    var sentHeaders: [Field] = []
    var headerBytes = 0
    var error: ClientError?
    init(cancellation: CurlCancellation) { self.cancellation = cancellation }
    func append(_ bytes: UnsafeMutablePointer<CChar>?, size: Int, count: Int, header: Bool) -> Int {
        let (length, overflow) = size.multipliedReportingOverflow(by: count)
        guard !overflow, let bytes, !cancellation.isCancelled else { return 0 }
        let limit = header ? 256 * 1024 : 20 * 1024 * 1024
        guard length <= limit - (header ? headerBytes : body.count) else {
            error = ClientError(header ? "Response headers exceed 256 KB." : "The response exceeds the 20 MB limit."); return 0
        }
        let buffer = UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self)
        if header {
            headerBytes += length
            let line = String(decoding: UnsafeBufferPointer(start: buffer, count: length), as: UTF8.self).trimmingCharacters(in: .newlines)
            if line.hasPrefix("HTTP/") { headers.removeAll() }
            else if let colon = line.firstIndex(of: ":") {
                let name = String(line[..<colon])
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers.append(Field(name, value))
                if name.lowercased() == "content-length", let expected = Int64(value), expected > 20 * 1024 * 1024 {
                    error = ClientError("The response exceeds the 20 MB limit."); return 0
                }
            }
        } else { body.append(buffer, count: length) }
        return length
    }
}
private let curlBodyCallback: curl_write_callback = { bytes, size, count, context in
    guard let context else { return 0 }
    return Unmanaged<CurlResponseBuffer>.fromOpaque(context).takeUnretainedValue().append(bytes, size: size, count: count, header: false)
}
private let curlHeaderCallback: curl_write_callback = { bytes, size, count, context in
    guard let context else { return 0 }
    return Unmanaged<CurlResponseBuffer>.fromOpaque(context).takeUnretainedValue().append(bytes, size: size, count: count, header: true)
}
private let curlCancelledCallback: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = { context in
    guard let context else { return 1 }
    return Unmanaged<CurlResponseBuffer>.fromOpaque(context).takeUnretainedValue().cancellation.isCancelled ? 1 : 0
}

// Capture only outgoing header blocks; libcurl debug text and TLS bytes are never logged.
private let curlDebugCallback: curl_debug_callback = { _, kind, bytes, count, context in
    guard kind == CURLINFO_HEADER_OUT, let bytes, let context, count < 256 * 1024 else { return 0 }
    let state = Unmanaged<CurlResponseBuffer>.fromOpaque(context).takeUnretainedValue()
    let text = String(decoding: UnsafeRawBufferPointer(start: bytes, count: count), as: UTF8.self)
    if text.hasPrefix("CONNECT ") { return 0 }
    state.sentHeaders = text.components(separatedBy: "\r\n").compactMap { line in
        guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return nil }
        return Field(String(line[..<colon]), String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }
    return 0
}

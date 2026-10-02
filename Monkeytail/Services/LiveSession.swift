import Foundation
import Observation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

@MainActor @Observable final class LiveSession {
    private(set) var events: [StreamEvent] = []
    private(set) var connected = false
    private(set) var connecting = false
    var error: String?
    var reconnect = false
    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var lastEventID: String?
    private var generation = UUID()
    func clear() { events = [] }
    func disconnect() { generation = UUID(); task?.cancel(); task = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil; session?.invalidateAndCancel(); session = nil; connected = false; connecting = false }
    func connect(_ model: APIRequest, variables: [String: String], proxy: ProxySettings, tls: TLSConfiguration? = nil, cookies: CookieJar? = nil) {
        disconnect(); error = nil; connecting = true; lastEventID = nil
        let current = generation
        task = Task { [self] in
            defer { if generation == current { connected = false; connecting = false; socket = nil; session?.invalidateAndCancel(); session = nil } }
            var retry = 2000
            repeat {
                do {
                    var model = model
                    guard model.impersonation == nil else { throw ClientError("WebSocket and SSE use System TLS. Select System in Request → Auth.") }
                    let websocket = model.transport == .websocket
                    if websocket {
                        guard var url = URLComponents(string: try RequestBuilder.resolve(model.url, variables: variables)), ["ws", "wss"].contains(url.scheme ?? "") else { throw ClientError("Enter a ws:// or wss:// URL.") }
                        url.scheme = url.scheme == "wss" ? "https" : "http"; model.url = url.string ?? model.url
                    }
                    model.bodyKind = .none; model.requestSchema = nil
                    var request = try RequestBuilder.build(model, variables: variables)
                    if let url = request.url, let cookies, request.value(forHTTPHeaderField: "Cookie") == nil {
                        let value = cookies.header(for: url)
                        if !value.isEmpty { model.headers.append(Field("Cookie", value)); request = try RequestBuilder.build(model, variables: variables) }
                    }
                    if websocket, var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) { url.scheme = url.scheme == "https" ? "wss" : "ws"; request.url = url.url }
                    let configuration = try HTTPClient.configuration(proxy: proxy, timeout: model.timeout)
                    configuration.timeoutIntervalForResource = 86400
                    let delegate = LiveTLSDelegate(identity: tls, original: request, followRedirects: model.followRedirects) { [weak self] in Task { @MainActor [weak self] in guard self?.generation == current else { return }; self?.connected = true; self?.connecting = false } }
                    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil); self.session = session
                    if websocket {
                        let socket = session.webSocketTask(with: request); socket.maximumMessageSize = 1024 * 1024; self.socket = socket; socket.resume()
                        while !Task.isCancelled {
                            let message = try await socket.receive(); try Task.checkCancellation(); guard generation == current else { return }; connected = true; connecting = false
                            switch message {
                            case .string(let text): append(StreamEvent(direction: "Received", type: "Text", text: text))
                            case .data(let data): append(StreamEvent(direction: "Received", type: "Binary", text: "\(data.count) bytes", binary: data))
                            @unknown default: break
                            }
                        }
                    } else {
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        if let lastEventID { request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID") }
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else { throw ClientError("Expected HTTP 200 with text/event-stream.") }
                        connected = true; connecting = false
                        var parser = SSEParser(), line = Data(), carriageReturn = false
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            if byte == 10 || byte == 13 {
                                if byte == 10 && carriageReturn { carriageReturn = false; continue }
                                if let event = try parser.consume(String(decoding: line, as: UTF8.self)) { append(event) }
                                line.removeAll(keepingCapacity: true); carriageReturn = byte == 13; lastEventID = parser.lastEventID; retry = parser.retryMilliseconds ?? retry
                            } else { carriageReturn = false; line.append(byte); guard line.count <= 64 * 1024 else { throw ClientError("SSE line exceeds 64 KB.") } }
                        }
                    }
                    if !reconnect { break }
                } catch {
                    if Task.isCancelled { break }; self.error = error.localizedDescription
                    append(StreamEvent(direction: "System", type: "Error", text: error.localizedDescription))
                    if !reconnect { break }
                }
                guard generation == current else { return }
                connected = false; session?.invalidateAndCancel(); session = nil; socket = nil
                try? await Task.sleep(for: .milliseconds(max(250, retry)))
            } while reconnect && !Task.isCancelled && generation == current
        }
    }
    func send(_ text: String, binary: Bool) {
        guard let socket else { return }
        let current = generation
        Task {
            do {
                if binary {
                    let compact = text.components(separatedBy: .whitespacesAndNewlines).joined()
                    guard compact.count % 2 == 0, compact.count <= 2 * 1024 * 1024 else { throw ClientError("Enter even-length hex up to 1 MB.") }
                    var data = Data(); var index = compact.startIndex
                    while index < compact.endIndex { let next = compact.index(index, offsetBy: 2); guard let byte = UInt8(compact[index..<next], radix: 16) else { throw ClientError("Invalid hex byte.") }; data.append(byte); index = next }
                    try await socket.send(.data(data)); guard generation == current else { return }; append(StreamEvent(direction: "Sent", type: "Binary", text: "\(data.count) bytes", binary: data))
                } else { guard text.utf8.count <= 1024 * 1024 else { throw ClientError("Message exceeds 1 MB.") }; try await socket.send(.string(text)); guard generation == current else { return }; append(StreamEvent(direction: "Sent", type: "Text", text: text)) }
            } catch { if generation == current { self.error = error.localizedDescription } }
        }
    }
    func ping() { let current = generation; socket?.sendPing { [weak self] error in Task { @MainActor [weak self] in guard self?.generation == current else { return }; if let error { self?.error = error.localizedDescription } else { self?.append(StreamEvent(direction: "System", type: "Ping", text: "Pong")) } } } }
    private func append(_ event: StreamEvent) {
        events.append(event)
        while events.count > 500 || events.reduce(0, { $0 + $1.text.utf8.count + ($1.binary?.count ?? 0) }) > 8 * 1024 * 1024 { events.removeFirst() }
    }
}
private final class LiveTLSDelegate: NSObject, URLSessionTaskDelegate, URLSessionWebSocketDelegate, @unchecked Sendable {
    let identity: TLSConfiguration?
    let original: URLRequest
    let followRedirects: Bool
    let opened: @Sendable () -> Void
    init(identity: TLSConfiguration?, original: URLRequest, followRedirects: Bool, opened: @escaping @Sendable () -> Void) { self.identity = identity; self.original = original; self.followRedirects = followRedirects; self.opened = opened }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard followRedirects, request.url?.scheme == original.url?.scheme, request.url?.host == original.url?.host, request.url?.port == original.url?.port else { completionHandler(nil); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) { opened() }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodClientCertificate, let identity, space.host.lowercased() == identity.host, space.port == identity.port {
            completionHandler(.useCredential, URLCredential(identity: identity.identity, certificates: identity.certificates, persistence: .forSession))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
}

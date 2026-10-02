import Foundation
import Network
import Observation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

@MainActor @Observable final class MockServer {
    private(set) var address: String?
    var error: String?
    private var listener: NWListener?
    private var generation = UUID()
    private var connections: [UUID: NWConnection] = [:]
    private var jobs: [UUID: Task<Void, Never>] = [:]
    func stop() { generation = UUID(); listener?.cancel(); listener = nil; connections.values.forEach { $0.cancel() }; connections = [:]; jobs.values.forEach { $0.cancel() }; jobs = [:]; address = nil }
    func start(_ requests: [APIRequest], variables: [String: String]) {
        stop(); error = nil
        do {
            var routes: [String: MockResponse] = [:]
            for request in requests {
                guard let mock = request.mock, mock.enabled else { continue }
                let url = URL(string: try RequestBuilder.resolve(request.url, variables: variables))
                let key = request.method.uppercased() + " " + (url?.path.isEmpty == false ? url!.path : "/")
                guard routes[key] == nil else { throw ClientError("Duplicate mock route: " + key) }
                routes[key] = mock
            }
            guard !routes.isEmpty else { throw ClientError("Enable a mock on at least one request.") }
            let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let listener = try NWListener(using: parameters); self.listener = listener
            let current = generation
            listener.stateUpdateHandler = { [weak self, weak listener] state in Task { @MainActor in
                guard self?.generation == current else { return }
                if case .ready = state, let port = listener?.port { self?.address = "http://127.0.0.1:\(port.rawValue)" }
                if case .failed(let error) = state { self?.error = error.localizedDescription; self?.stop() }
            } }
            let capturedRoutes = routes
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in guard self?.generation == current else { connection.cancel(); return }; self?.accept(connection, routes: capturedRoutes) } }
            listener.start(queue: DispatchQueue(label: "co.kitta.monkeytail.mocks"))
        } catch { self.error = error.localizedDescription }
    }
    private func accept(_ connection: NWConnection, routes: [String: MockResponse]) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection; connection.start(queue: .global(qos: .utility))
        jobs[id] = Task {
            defer { connections[id]?.cancel(); connections[id] = nil; jobs[id] = nil }
            do {
                var buffer = Data()
                while buffer.range(of: Data("\r\n\r\n".utf8)) == nil {
                    let chunk: Data = try await withCheckedThrowingContinuation { continuation in connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, complete, error in
                        if let error { continuation.resume(throwing: error) } else if let data, !data.isEmpty { continuation.resume(returning: data) } else { continuation.resume(throwing: ClientError(complete ? "Connection closed." : "Empty request.")) }
                    } }
                    buffer.append(chunk); guard buffer.count <= 64 * 1024 else { throw ClientError("Request headers exceed 64 KB.") }; try Task.checkCancellation()
                }
                let first = String(decoding: buffer, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
                let pieces = first.split(separator: " "); guard pieces.count == 3 else { throw ClientError("Invalid HTTP request.") }
                let path = String(pieces[1]).components(separatedBy: "?").first ?? "/"
                var missing = MockResponse(); missing.status = 404; missing.body = "{\"error\":\"No matching mock\"}"
                let mock = routes[String(pieces[0]).uppercased() + " " + path] ?? missing
                if let failure = mock.simulatedError, !failure.isEmpty { return }
                let response = try await mock.response(url: address ?? "")
                let body = String(pieces[0]) == "HEAD" ? Data() : response.body
                var headers = "HTTP/1.1 \(response.status) Mock\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
                for field in response.headers where field.enabled && !["content-length", "connection", "transfer-encoding", "content-encoding"].contains(field.name.lowercased()) && !field.name.contains("\r") && !field.name.contains("\n") && !field.value.contains("\r") && !field.value.contains("\n") { headers += field.name + ": " + field.value + "\r\n" }
                var bytes = Data((headers + "\r\n").utf8); bytes.append(body)
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in connection.send(content: bytes, completion: .contentProcessed { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        // Slow or incomplete local clients cannot keep a slot forever.
        Task { [weak self] in try? await Task.sleep(for: .seconds(35)); self?.jobs[id]?.cancel(); self?.connections[id]?.cancel() }
    }
}

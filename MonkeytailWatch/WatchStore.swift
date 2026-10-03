import Foundation
import Observation
import WatchConnectivity
import MonkeytailWatchCore

@MainActor @Observable final class WatchStore: NSObject, WCSessionDelegate {
    private(set) var requests: [WatchRequest] = []
    private(set) var responses: [UUID: WatchResponse] = [:]
    private(set) var runningID: UUID?
    var issue: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let vault = WatchVault()
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private var unavailable = false
    override init() {
        super.init(); reload()
        if testing {
            var sample = WatchRequest.sample
            sample.url = ProcessInfo.processInfo.environment["MONKEYTAIL_TEST_URL"] ?? "http://127.0.0.1:8766/echo"
            requests = [sample]
        } else if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func reload() {
        guard !testing else { return }
        do { requests = try vault.load() ?? []; unavailable = false; issue = nil }
        catch { issue = error.localizedDescription; unavailable = true }
    }
    func receive(_ data: Data, useKeychain: Bool? = nil) throws {
        let value = try WatchPayload.decode(data)
        if !testing { try vault.save(value, useKeychain: useKeychain) }
        cancel(); requests = value; responses = [:]; unavailable = false; issue = nil
    }
    func remove(_ id: UUID) {
        guard !unavailable else { return }
        do {
            let next = requests.filter { $0.id != id }; if !testing { try vault.save(next) }
            if runningID == id { cancel() }; requests = next; responses[id] = nil
        } catch { issue = error.localizedDescription }
    }
    func send(_ request: WatchRequest) {
        cancel(); issue = nil; runningID = request.id; let token = generation
        task = Task { [weak self] in
            do {
                let response = try await WatchHTTPClient(request).send()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                if self.responses.count >= 4 { self.responses = [:] }
                self.responses[request.id] = response
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.issue = error.localizedDescription
            }
            if let self, self.generation == token { self.runningID = nil; self.task = nil }
        }
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; runningID = nil }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if session.receivedApplicationContext["version"] as? Int == 1, let data = session.receivedApplicationContext["requests"] as? Data { consume(data, useKeychain: session.receivedApplicationContext["useKeychain"] as? Bool) }
        if let error { Task { @MainActor in self.issue = error.localizedDescription } }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard applicationContext["version"] as? Int == 1, let data = applicationContext["requests"] as? Data else { return }
        consume(data, useKeychain: applicationContext["useKeychain"] as? Bool)
    }
    nonisolated private func consume(_ data: Data, useKeychain: Bool?) {
        guard data.count <= WatchPayload.maximumBytes else { return }
        Task { @MainActor in do { try self.receive(data, useKeychain: useKeychain) } catch { self.issue = error.localizedDescription } }
    }
}

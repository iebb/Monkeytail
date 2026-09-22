import SwiftUI
import Observation
import MonkeytailCore

@MainActor @Observable
final class WorkspaceStore {
    var workspace: Workspace { didSet { scheduleSave() } }
    var selectedRequestID: UUID?
    var responses: [UUID: APIResponse] = [:]
    var errors: [UUID: String] = [:]
    var history: [HistoryEntry] = []
    var runningID: UUID?
    var issue: String?
    var notice: String?
    private var sendTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private let directory: URL

    init(directory: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        self.directory = directory ?? (testing ? FileManager.default.temporaryDirectory.appendingPathComponent("MonkeytailUITests") : URL.applicationSupportDirectory.appendingPathComponent("Monkeytail", isDirectory: true))
        let location = self.directory.appendingPathComponent("workspace.json")
        if !testing, FileManager.default.fileExists(atPath: location.path) {
            do {
                workspace = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: location))
                guard workspace.version == 1 else { throw ClientError("Unsupported saved workspace version.") }
            } catch {
                // Preserve the original file before offering a fresh workspace.
                let backup = self.directory.appendingPathComponent("workspace-recovery-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: location, to: backup)
                workspace = .starter
                issue = "The saved workspace could not be loaded. A recovery copy was retained. \(error.localizedDescription)"
            }
        } else { workspace = .starter }
        if !testing, let data = try? Data(contentsOf: self.directory.appendingPathComponent("history.json")), let loaded = try? JSONDecoder().decode([HistoryEntry].self, from: data) { history = loaded }
        if testing, let url = ProcessInfo.processInfo.environment["MONKEYTAIL_TEST_URL"] { workspace.collections[0].requests[0].url = url }
        selectedRequestID = workspace.collections.first?.requests.first?.id
    }

    var selectedRequest: APIRequest? { request(selectedRequestID) }
    var environment: APIEnvironment? { workspace.environments.first { $0.id == workspace.selectedEnvironmentID } }
    var variables: [String: String] { environment?.values ?? [:] }
    var requestCount: Int { workspace.collections.reduce(0) { $0 + $1.requests.count } }

    func request(_ id: UUID?) -> APIRequest? { workspace.collections.lazy.flatMap(\.requests).first { $0.id == id } }
    func update(_ request: APIRequest) {
        for c in workspace.collections.indices {
            if let r = workspace.collections[c].requests.firstIndex(where: { $0.id == request.id }) { workspace.collections[c].requests[r] = request; return }
        }
    }
    func binding(for id: UUID) -> Binding<APIRequest> {
        Binding(get: { self.request(id) ?? APIRequest() }, set: { self.update($0) })
    }
    func addRequest(to collectionID: UUID? = nil) {
        if workspace.collections.isEmpty { workspace.collections.append(RequestCollection(name: "My collection")) }
        let index = workspace.collections.firstIndex { $0.id == collectionID } ?? 0
        let request = APIRequest()
        workspace.collections[index].requests.append(request); selectedRequestID = request.id
    }
    func duplicate(_ request: APIRequest) {
        var copy = request; copy.id = UUID(); copy.name += " copy"
        let index = workspace.collections.firstIndex { $0.requests.contains { $0.id == request.id } } ?? 0
        workspace.collections[index].requests.append(copy); selectedRequestID = copy.id
    }
    func delete(_ id: UUID) {
        for index in workspace.collections.indices { workspace.collections[index].requests.removeAll { $0.id == id } }
        responses[id] = nil; errors[id] = nil
        if selectedRequestID == id { selectedRequestID = workspace.collections.first?.requests.first?.id }
    }
    func restore(_ entry: HistoryEntry) {
        var request = entry.request; request.id = UUID(); request.name += " · replay"
        if workspace.collections.isEmpty { workspace.collections.append(RequestCollection(name: "History")) }
        workspace.collections[0].requests.append(request); selectedRequestID = request.id
    }
    func importContent(_ text: String) throws {
        guard text.utf8.count <= 10 * 1024 * 1024 else { throw ClientError("Imports must be smaller than 10 MB.") }
        let command = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if command == "curl" || command.hasSuffix("/curl") {
            let result = try CurlCodec.decode(text)
            let collection = RequestCollection(name: "Imported cURL", requests: [result.request])
            workspace.collections.append(collection); selectedRequestID = result.request.id
            if let proxy = result.proxy { workspace.proxy = proxy }
            notice = (["Imported 1 request."] + result.warnings).joined(separator: "\n\n")
        } else {
            let result = try CollectionCodec.decode(Data(text.utf8))
            var incoming = result.workspace
            let originalSelected = incoming.selectedEnvironmentID
            var importedSelection: UUID?
            for c in incoming.collections.indices {
                incoming.collections[c].id = UUID()
                for r in incoming.collections[c].requests.indices {
                    incoming.collections[c].requests[r].id = UUID()
                    incoming.collections[c].requests[r].scriptsEnabled = false
                }
            }
            for e in incoming.environments.indices {
                let old = incoming.environments[e].id
                incoming.environments[e].id = UUID()
                if old == originalSelected { importedSelection = incoming.environments[e].id }
            }
            workspace.collections += incoming.collections
            workspace.environments += incoming.environments
            if result.includesSettings { workspace.proxy = incoming.proxy }
            if let selected = importedSelection ?? incoming.environments.first?.id { workspace.selectedEnvironmentID = selected }
            selectedRequestID = incoming.collections.first?.requests.first?.id ?? selectedRequestID
            let count = incoming.collections.reduce(0) { $0 + $1.requests.count }
            notice = (["Imported \(count) requests and \(incoming.environments.count) environments."] + result.warnings).joined(separator: "\n\n")
        }
    }

    func send() {
        guard let saved = selectedRequest, runningID == nil else { return }
        runningID = saved.id; errors[saved.id] = nil
        let environmentID = workspace.selectedEnvironmentID
        let initialVariables = variables
        let proxy = workspace.proxy
        sendTask = Task {
            defer { runningID = nil; sendTask = nil }
            var request = saved, variables = initialVariables, logs: [ScriptLog] = []
            do {
                if saved.scriptsEnabled && !saved.preScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let result = try await ScriptRunner().run(saved.preScript, request: request, variables: variables)
                    request.method = result.request.method; request.url = result.request.url
                    request.headers = result.request.headers.sorted { $0.key < $1.key }.map { Field($0.key, $0.value) }
                    if request.body != result.request.body && request.bodyKind == .none { request.bodyKind = .text }
                    request.body = result.request.body
                    variables = result.variables; logs += result.logs.map { ScriptLog($0.level, $0.message) }
                    applyVariables(variables, to: environmentID)
                }
                try Task.checkCancellation()
                let built = try RequestBuilder.build(request, variables: variables)
                var response = try await HTTPClient(followRedirects: request.followRedirects).send(built, proxy: proxy)
                if saved.scriptsEnabled && !saved.postScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        let result = try await ScriptRunner().run(saved.postScript, request: request, response: response, variables: variables)
                        logs += result.logs.map { ScriptLog($0.level, $0.message) }
                        applyVariables(result.variables, to: environmentID)
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        logs.append(ScriptLog("error", error.localizedDescription))
                    }
                }
                response.logs = logs
                responses[saved.id] = response
                // Keep a bounded working set on memory-constrained devices.
                while responses.count > 8 || responses.values.reduce(0, { $0 + $1.body.count }) > 40 * 1024 * 1024 {
                    guard let oldest = responses.filter({ $0.key != saved.id }).min(by: { $0.value.receivedAt < $1.value.receivedAt })?.key else { break }
                    responses[oldest] = nil
                }
                history.insert(HistoryEntry(request: saved, status: response.status, duration: response.duration), at: 0)
            } catch {
                let message = Task.isCancelled ? "Request cancelled." : error.localizedDescription
                errors[saved.id] = message
                history.insert(HistoryEntry(request: saved, status: nil, duration: 0, error: message), at: 0)
            }
            history = Array(history.prefix(50)); persistHistory()
        }
    }
    func cancel() { sendTask?.cancel() }
    func clearHistory() { history = []; persistHistory() }
    private func applyVariables(_ values: [String: String], to id: UUID?) {
        guard let index = workspace.environments.firstIndex(where: { $0.id == id }) else { return }
        let disabled = workspace.environments[index].variables.filter { !$0.enabled && values[$0.name] == nil }
        workspace.environments[index].variables = values.keys.sorted().map { Field($0, values[$0]!) } + disabled
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }; self?.save()
        }
    }
    func save() {
        do { try write(JSONEncoder().encode(workspace), name: "workspace.json") }
        catch { issue = "Could not save the workspace: \(error.localizedDescription)" }
    }
    private func persistHistory() {
        do { try write(JSONEncoder().encode(history), name: "history.json") }
        catch { issue = "Could not save history: \(error.localizedDescription)" }
    }
    private func write(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

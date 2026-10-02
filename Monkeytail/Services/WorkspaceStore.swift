import SwiftUI
import Observation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

@MainActor @Observable
final class WorkspaceStore {
    var workspace: Workspace { didSet { workspaceChanged(); scheduleSave() } }
    var selectedRequestID: UUID?
    private(set) var responses: [UUID: PreparedResponse] = [:]
    var errors: [UUID: String] = [:]
    var history: [HistoryEntry] = []
    var runningID: UUID?
    var testResults: [UUID: [AssertionResult]] = [:]
    let network: LocalNetworkStorage
    let mockServer = MockServer()
    var issue: String?
    var notice: String?
    private var sendTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private let directory: URL
    private let vault: SecretVault
    private let snapshotStorage: SnapshotStorage
    private let persistence = WorkspacePersistence()
    private var syncState = WorkspaceSyncState()
    private var applyingSync = false
    private var vaultUnavailable = false
    private var syncTask: Task<Void, Never>?
    private var cloud = ICloudWorkspace()
    private var settings: LocalSettings = LocalSettings()
    private(set) var snapshots: [SnapshotSummary] = []
    private(set) var syncStatus = "Off"
    private(set) var syncing = false
    var syncEnabled: Bool { settings.syncEnabled }
    private struct LocalSettings: Codable { var syncEnabled = false; var edited = false; var identity: Data? }


    init(directory: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        self.directory = directory ?? (testing ? FileManager.default.temporaryDirectory.appendingPathComponent("MonkeytailUITests") : URL.applicationSupportDirectory.appendingPathComponent("Monkeytail", isDirectory: true))
        if testing { try? FileManager.default.removeItem(at: self.directory) }
        network = LocalNetworkStorage(directory: self.directory)
        vault = SecretVault(directory: self.directory)
        snapshotStorage = SnapshotStorage(directory: self.directory)
        let location = self.directory.appendingPathComponent("workspace.json")
        if !testing, FileManager.default.fileExists(atPath: location.path) {
            do {
                workspace = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: location))
                do { workspace = SecretPolicy.restore(workspace, secrets: try vault.load()) }
                catch { vaultUnavailable = true; issue = error.localizedDescription }
                guard workspace.version == 1 else { throw ClientError("Unsupported saved workspace version.") }
            } catch {
                // Preserve the original file before offering a fresh workspace.
                let backup = self.directory.appendingPathComponent("workspace-recovery-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: location, to: backup)
                workspace = .starter
                issue = "The saved workspace could not be loaded. A recovery copy was retained. \(error.localizedDescription)"
            }
        } else { workspace = .starter }
        if !testing, let data = try? Data(contentsOf: self.directory.appendingPathComponent("history.json")), let loaded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            let secrets = (try? vault.load()) ?? [:]
            history = loaded.map { entry in
                var entry = entry
                let value = SecretPolicy.restore(Workspace(collections: [RequestCollection(name: "History", requests: [entry.request])]), secrets: secrets)
                entry.request = value.collections[0].requests[0]; return entry
            }
        }
        if testing, let url = ProcessInfo.processInfo.environment["MONKEYTAIL_TEST_URL"] { workspace.collections[0].requests[0].url = url }
        selectedRequestID = workspace.collections.first?.requests.first?.id
        if !testing {
            if let data = try? Data(contentsOf: self.directory.appendingPathComponent("sync-state.json")), let state = try? JSONDecoder().decode(WorkspaceSyncState.self, from: data) { syncState = state }
            if let data = try? Data(contentsOf: self.directory.appendingPathComponent("settings.json")), let saved = try? JSONDecoder().decode(LocalSettings.self, from: data) { settings = saved }
            else { settings.edited = FileManager.default.fileExists(atPath: location.path) }
        }
        Task { await refreshSnapshots() }
        if settings.syncEnabled { cloud = ICloudWorkspace(accountIdentity: settings.identity); startSyncLoop() }
    }

    var selectedRequest: APIRequest? { request(selectedRequestID) }
    var environment: APIEnvironment? { workspace.environments.first { $0.id == workspace.selectedEnvironmentID } }
    var variables: [String: String] { environment?.values ?? [:] }
    var requestCount: Int { workspace.collections.reduce(0) { $0 + $1.requests.count } }

    func request(_ id: UUID?) -> APIRequest? { workspace.collections.lazy.flatMap(\.requests).first { $0.id == id } }
    private func attachmentBytes(_ request: APIRequest) -> Int {
        (request.fileBody?.data?.count ?? 0) + (request.multipart ?? []).reduce(0) { $0 + ($1.file?.data?.count ?? 0) }
    }
    private var workspaceAttachmentBytes: Int { workspace.collections.flatMap(\.requests).reduce(0) { $0 + attachmentBytes($1) } }
    func update(_ request: APIRequest) {
        let oldBytes = self.request(request.id).map(attachmentBytes) ?? 0
        guard workspaceAttachmentBytes - oldBytes + attachmentBytes(request) <= 40 * 1024 * 1024 else {
            issue = "Workspace attachments exceed 40 MB. Remove a file before adding more."; return
        }
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
        guard workspaceAttachmentBytes + attachmentBytes(request) <= 40 * 1024 * 1024 else { issue = "Workspace attachments exceed 40 MB."; return }
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
        var request = entry.request
        if let original = self.request(request.id) {
            if request.fileBody?.filename == original.fileBody?.filename { request.fileBody?.data = original.fileBody?.data }
            if request.multipart != nil { for index in request.multipart!.indices {
                if let file = original.multipart?.first(where: { $0.id == request.multipart![index].id })?.file,
                   file.filename == request.multipart![index].file?.filename { request.multipart![index].file?.data = file.data }
            } }
        }
        guard workspaceAttachmentBytes + attachmentBytes(request) <= 40 * 1024 * 1024 else { issue = "Workspace attachments exceed 40 MB."; return }
        let destination = workspace.collections.firstIndex { $0.requests.contains { $0.id == request.id } } ?? 0
        if !workspace.collections.indices.contains(destination) || !(workspace.collections[destination].folders ?? []).contains(where: { $0.id == request.folderID }) { request.folderID = nil }
        request.id = UUID(); request.name += " · replay"
        if workspace.collections.isEmpty { workspace.collections.append(RequestCollection(name: "History")) }
        workspace.collections[destination].requests.append(request); selectedRequestID = request.id
    }
    func importContent(_ text: String) throws {
        guard text.utf8.count <= 40 * 1024 * 1024 else { throw ClientError("Imports must be smaller than 40 MB.") }
        let command = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        if CurlCodec.isCommand(command) {
            let result = try CurlCodec.decode(text)
            let collection = RequestCollection(name: "Imported cURL", requests: [result.request])
            workspace.collections.append(collection); selectedRequestID = result.request.id
            if let proxy = result.proxy { workspace.proxy = proxy }
            notice = (["Imported 1 request."] + result.warnings).joined(separator: "\n\n")
        } else {
            let data = Data(text.utf8)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let specification = object?["openapi"] != nil || object?["swagger"] != nil || (object == nil && (text.contains("openapi:") || text.contains("swagger:")))
            let result = try specification ? OpenAPICodec.decode(data) : CollectionCodec.decode(data)
            var incoming = result.workspace
            let incomingBytes = incoming.collections.flatMap(\.requests).reduce(0) { $0 + attachmentBytes($1) }
            guard workspaceAttachmentBytes + incomingBytes <= 40 * 1024 * 1024 else { throw ClientError("Workspace attachments exceed 40 MB.") }
            let originalSelected = incoming.selectedEnvironmentID
            var importedSelection: UUID?
            for c in incoming.collections.indices {
                incoming.collections[c].id = UUID()
                let folderIDs = Dictionary((incoming.collections[c].folders ?? []).map { ($0.id, UUID()) }, uniquingKeysWith: { first, _ in first })
                incoming.collections[c].folders = incoming.collections[c].folders.map { $0.map { folder in
                    var folder = folder; folder.id = folderIDs[folder.id]!; folder.parentID = folder.parentID.flatMap { folderIDs[$0] }; folder.defaults.scriptsEnabled = false; return folder
                } }
                incoming.collections[c].defaults?.scriptsEnabled = false
                for r in incoming.collections[c].requests.indices {
                    incoming.collections[c].requests[r].id = UUID()
                    incoming.collections[c].requests[r].folderID = incoming.collections[c].requests[r].folderID.flatMap { folderIDs[$0] }
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
        guard let saved = selectedRequest, runningID == nil, saved.transport != .websocket, saved.transport != .sse else { return }
        runningID = saved.id; errors[saved.id] = nil
        let environmentID = workspace.selectedEnvironmentID
        let environmentVariables = variables
        let proxy = workspace.proxy
        sendTask = Task {
            defer { runningID = nil; sendTask = nil }
            var request = saved, variables = environmentVariables, logs: [ScriptLog] = []
            do {
                let resolved = try effective(saved)
                request = resolved.request; variables = resolved.variables
                let initialVariables = variables
                if request.auth.kind == .oauth2, let oauth = request.auth.oauth, let expires = oauth.expiresAt, expires < Date().addingTimeInterval(30), !oauth.refreshToken.isEmpty {
                    request.auth.oauth = try await OAuthAuthorizer().refresh(oauth, proxy: proxy)
                    persistAuth(request.auth, for: saved)
                }
                if request.scriptsEnabled && !request.preScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let result = try await ScriptRunner().run(request.preScript, request: request, variables: variables)
                    request.method = result.request.method; request.url = result.request.url
                    request.headers = result.request.headers.sorted { $0.key < $1.key }.map { Field($0.key, $0.value) }
                    if request.body != result.request.body && request.bodyKind == .none { request.bodyKind = .text }
                    request.body = result.request.body
                    variables = result.variables; logs += result.logs.map { ScriptLog($0.level, $0.message) }
                    applyScriptVariables(variables, original: initialVariables, to: environmentID)
                }
                try Task.checkCancellation()
                var built = try RequestBuilder.build(request, variables: variables)
                let cookiesEnabled = request.cookieJarEnabled ?? false
                if cookiesEnabled, let issue = network.issue { throw ClientError(issue) }
                let jar = cookiesEnabled ? network.jar(environmentID) : nil
                if let url = built.url, let jar, built.value(forHTTPHeaderField: "Cookie") == nil {
                    let value = jar.header(for: url)
                    if !value.isEmpty {
                        request.headers.append(Field("Cookie", value))
                        built = try RequestBuilder.build(request, variables: variables)
                    }
                }
                var response: APIResponse
                if let mock = request.mock, mock.enabled { response = try await mock.response(url: built.url!.absoluteString) }
                else {
                    let protectedHeaders = request.headers.filter(\.isSecret).map(\.name) + (request.auth.apiKey.map { $0.inQuery ? [] : [$0.name] } ?? [])
                    response = try await HTTPClient(followRedirects: request.followRedirects).send(built, proxy: proxy, impersonation: request.impersonation, cookies: jar, tls: network.identity(for: built.url), sensitiveHeaders: protectedHeaders)
                }
                if cookiesEnabled, let received = response.sessionCookies { var jar = CookieJar(); jar.cookies = received; try network.setJar(jar, environment: environmentID) }
                let assertionResults = await Task.detached { [request, response] in ResponseTests.evaluate(request.assertions ?? [], response: response, schema: request.responseSchema) }.value
                testResults[saved.id] = assertionResults
                logs += assertionResults.map { ScriptLog($0.passed ? "pass" : "fail", $0.name + ": " + $0.message) }
                if request.scriptsEnabled && !request.postScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    do {
                        let result = try await ScriptRunner().run(request.postScript, request: request, response: response, variables: variables)
                        logs += result.logs.map { ScriptLog($0.level, $0.message) }
                        applyScriptVariables(result.variables, original: variables, to: environmentID)
                    } catch {
                        if Task.isCancelled { throw CancellationError() }
                        logs.append(ScriptLog("error", error.localizedDescription))
                    }
                }
                response.logs = logs
                let prepared = await Task.detached(priority: .userInitiated) { [response] in
                    PreparedResponse(response: response)
                }.value
                try Task.checkCancellation()
                responses[saved.id] = prepared
                // Keep a bounded working set on memory-constrained devices.
                while responses.count > 8 || responses.values.reduce(0, { $0 + $1.response.body.count }) > 40 * 1024 * 1024 {
                    guard let oldest = responses.filter({ $0.key != saved.id }).min(by: { $0.value.response.receivedAt < $1.value.response.receivedAt })?.key else { break }
                    responses[oldest] = nil
                }
                history.insert(HistoryEntry(request: saved, status: response.status, duration: response.duration), at: 0)
            } catch {
                let message = Task.isCancelled ? "Request cancelled." : error.localizedDescription
                errors[saved.id] = message
                history.insert(HistoryEntry(request: saved, status: nil, duration: 0, error: message), at: 0)
            }
            history = Array(history.prefix(50)).map { entry in
                var entry = entry; entry.request.fileBody?.data = nil
                if entry.request.multipart != nil { for index in entry.request.multipart!.indices { entry.request.multipart![index].file?.data = nil } }
                return entry
            }; persistHistory()
        }
    }
    func effective(_ request: APIRequest) throws -> ResolvedRequest {
        try RequestInheritance.resolve(request, collection: workspace.collections.first { $0.requests.contains { $0.id == request.id } }, environment: variables)
    }
    func persistAuth(_ auth: RequestAuth, for request: APIRequest) {
        guard let c = workspace.collections.firstIndex(where: { $0.requests.contains { $0.id == request.id } }) else { return }
        if request.auth.kind != .inherit { var value = request; value.auth = auth; update(value); return }
        var parent = request.folderID, visited = Set<UUID>()
        while let id = parent, visited.insert(id).inserted, let index = workspace.collections[c].folders?.firstIndex(where: { $0.id == id }) {
            if workspace.collections[c].folders![index].defaults.auth.kind != .inherit { workspace.collections[c].folders![index].defaults.auth = auth; return }
            parent = workspace.collections[c].folders![index].parentID
        }
        workspace.collections[c].defaults?.auth = auth
    }
    private func applyScriptVariables(_ values: [String: String], original: [String: String], to id: UUID?) {
        guard let index = workspace.environments.firstIndex(where: { $0.id == id }) else { return }
        var result = workspace.environments[index].values
        for (key, value) in values where original[key] != value { result[key] = value }
        for key in original.keys where values[key] == nil { result[key] = nil }
        applyVariables(result, to: id)
    }
    func cancel() { sendTask?.cancel() }
    func clearHistory() { history = []; persistHistory() }
    private func applyVariables(_ values: [String: String], to id: UUID?) {
        guard let index = workspace.environments.firstIndex(where: { $0.id == id }) else { return }
        let disabled = workspace.environments[index].variables.filter { !$0.enabled && values[$0.name] == nil }
        let old = workspace.environments[index].variables
        workspace.environments[index].variables = values.keys.sorted().map { name in
            var field = old.first { $0.name == name } ?? Field(name)
            field.value = values[name]!; return field
        } + disabled
    }
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }; self?.saveInBackground()
        }
    }
    private func persistenceSnapshot() throws -> WorkspacePersistence.Snapshot {
        guard !vaultUnavailable else { throw ClientError("Unlock the device and reopen Monkeytail to load credentials.") }
        var secrets: [String: String] = [:]
        let protectedHistory = history.map { entry in
            var copy = entry
            let value = SecretPolicy.strip(Workspace(collections: [RequestCollection(name: "History", requests: [entry.request])]), secrets: &secrets, files: false)
            copy.request = value.collections[0].requests[0]; return copy
        }
        // Current credentials take precedence over older history definitions.
        let protected = SecretPolicy.strip(workspace, secrets: &secrets, files: false)
        return WorkspacePersistence.Snapshot(workspace: protected, history: protectedHistory, sync: syncState,
            settings: try JSONEncoder().encode(settings), secrets: secrets, directory: directory)
    }
    private func saveInBackground() {
        do {
            persistence.enqueue(try persistenceSnapshot()) { [weak self] message in
                guard let message else { return }
                Task { @MainActor in self?.issue = "Could not save the workspace: \(message)" }
            }
        } catch { issue = error.localizedDescription }
    }
    func save() {
        saveTask?.cancel()
        do { try persistence.save(persistenceSnapshot()) }
        catch { issue = "Could not save the workspace: \(error.localizedDescription)" }
    }
    func refreshSnapshots() async {
        do { snapshots = try await snapshotStorage.summaries() }
        catch { issue = "Could not load snapshots: \(error.localizedDescription)" }
    }
    func saveSnapshot(requestID: UUID, response: APIResponse) {
        guard let request = request(requestID) else { return }
        Task {
            do { snapshots = try await snapshotStorage.save(ResponseSnapshot(request: request, response: response)); notice = "Snapshot saved." }
            catch { issue = error.localizedDescription }
        }
    }
    func loadSnapshot(_ id: UUID) async throws -> ResponseSnapshot { try await snapshotStorage.load(id) }
    func useSnapshotAsMock(_ snapshot: ResponseSnapshot) throws {
        guard let text = String(data: snapshot.response.body, encoding: .utf8), snapshot.response.body.count <= 2 * 1024 * 1024 else { throw ClientError("Mocks require a UTF-8 response up to 2 MB.") }
        var mock = MockResponse(); mock.enabled = true; mock.status = snapshot.response.status; mock.body = text
        mock.headers = snapshot.response.headers.filter { !["content-length", "transfer-encoding", "content-encoding", "connection"].contains($0.name.lowercased()) }
        if let c = workspace.collections.firstIndex(where: { $0.requests.contains { $0.id == snapshot.requestID } }), let r = workspace.collections[c].requests.firstIndex(where: { $0.id == snapshot.requestID }) {
            workspace.collections[c].requests[r].mock = mock; selectedRequestID = snapshot.requestID
        } else {
            var request = APIRequest(name: snapshot.name, method: snapshot.method, url: snapshot.url); request.mock = mock
            workspace.collections.append(RequestCollection(name: "Mocks", requests: [request])); selectedRequestID = request.id
        }
        notice = "Offline mock saved."
    }
    func removeSnapshot(_ id: UUID) {
        Task { do { snapshots = try await snapshotStorage.remove(id) } catch { issue = error.localizedDescription } }
    }
    private func workspaceChanged() {
        guard !applyingSync else { return }
        settings.edited = true
        do { try syncState.capture(workspace) } catch { issue = error.localizedDescription }
    }
    func setSyncEnabled(_ enabled: Bool) {
        settings.syncEnabled = enabled
        syncTask?.cancel(); syncTask = nil
        if enabled { settings.identity = nil; cloud = ICloudWorkspace(); startSyncLoop() }
        else { syncStatus = "Off" }
        save()
    }
    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronize()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    func synchronize() async {
        guard settings.syncEnabled, !syncing, !vaultUnavailable else { return }
        syncing = true; syncStatus = "Syncing…"
        defer { syncing = false }
        do {
            let remote = try await cloud.read()
            settings.identity = await cloud.identity()
            guard settings.syncEnabled, !Task.isCancelled else { return }
            // Fresh installs adopt the existing workspace instead of uploading duplicate starter requests.
            if settings.edited || remote.isEmpty { try syncState.capture(workspace) }
            for state in remote { syncState.merge(state) }
            let merged = try syncState.workspace(local: workspace)
            if merged != workspace {
                var ignored: [String: String] = [:]
                try write(JSONEncoder().encode(SecretPolicy.strip(workspace, secrets: &ignored, files: false)), name: "workspace-before-sync.json")
                applyingSync = true; workspace = merged; applyingSync = false
                if request(selectedRequestID) == nil { selectedRequestID = workspace.collections.first?.requests.first?.id }
            }
            settings.edited = true
            save()
            try await cloud.write(syncState)
            guard settings.syncEnabled else { return }
            syncStatus = "Updated locally · iCloud transfers automatically"
        } catch {
            if !Task.isCancelled { syncStatus = error.localizedDescription }
        }
    }
    private func persistHistory() {
        saveInBackground()
    }
    private func write(_ data: Data, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

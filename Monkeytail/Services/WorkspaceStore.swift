import SwiftUI
import Observation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

@MainActor @Observable
final class WorkspaceStore {
    var workspace: Workspace { didSet { pruneTabs(); workspaceChanged(); scheduleSave() } }
    var selectedRequestID: UUID? { didSet { if let id = selectedRequestID { openTab(id) }; saveTabs() } }
    /// Open request tabs, in order; restored on the next launch.
    private(set) var openRequestIDs: [UUID] = [] { didSet { saveTabs() } }
    static let maximumTabs = 20
    private var persistsTabs = false
    private(set) var responses: [UUID: PreparedResponse] = [:]
    var errors: [UUID: String] = [:]
    var history: [HistoryEntry] = []
    var runningID: UUID?
    var collectionRun: CollectionRun?
    var testResults: [UUID: [AssertionResult]] = [:]
    /// The certificate a request's server presented when the system rejected it, offered for per-host trust.
    private(set) var untrustedCertificates: [UUID: TrustedCertificate] = [:]
    let network: LocalNetworkStorage
    let mockServer = MockServer()
    var issue: String?
    var notice: String?
    private var sendTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private let directory: URL
    private let managesWatchStorage: Bool
    private var vault: SecretVault
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
    var useKeychain: Bool { settings.useKeychain ?? false }
    var syncCredentials: Bool { settings.syncCredentials ?? false }
    var hideCredentials: Bool { settings.hideCredentials ?? true }
    var watchIncludesCredentials: Bool { settings.watchIncludesCredentials ?? false }
    private struct LocalSettings: Codable {
        var syncEnabled = false; var edited = false; var identity: Data?
        var useKeychain: Bool? = false
        var syncCredentials: Bool? = true
        var hideCredentials: Bool? = false
        var watchIncludesCredentials: Bool? = true
        var legacyKeychain: Bool?
    }


    init(directory: URL? = nil) {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        managesWatchStorage = directory == nil && !testing
        self.directory = directory ?? (testing ? FileManager.default.temporaryDirectory.appendingPathComponent("MonkeytailUITests") : URL.applicationSupportDirectory.appendingPathComponent("Monkeytail", isDirectory: true))
        if testing { try? FileManager.default.removeItem(at: self.directory) }
        let location = self.directory.appendingPathComponent("workspace.json")
        var savedSettings = LocalSettings()
        if !testing, let data = try? Data(contentsOf: self.directory.appendingPathComponent("settings.json")) {
            if let decoded = try? JSONDecoder().decode(LocalSettings.self, from: data) { savedSettings = decoded }
            else { savedSettings.useKeychain = nil }
        } else if !testing, FileManager.default.fileExists(atPath: location.path) { savedSettings.useKeychain = nil }
        if savedSettings.useKeychain == nil { savedSettings.legacyKeychain = true }
        settings = savedSettings
        let keychain = savedSettings.useKeychain ?? false
        network = LocalNetworkStorage(directory: self.directory, useKeychain: keychain)
        vault = SecretVault(directory: self.directory, useKeychain: keychain)
        snapshotStorage = SnapshotStorage(directory: self.directory)
        var loadedSecrets: [String: String] = [:]
        if !testing, FileManager.default.fileExists(atPath: location.path) {
            do {
                workspace = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: location))
                do {
                    if keychain || savedSettings.useKeychain == nil { loadedSecrets = try vault.load() }
                    workspace = SecretPolicy.restore(workspace, secrets: loadedSecrets)
                }
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
            history = loaded.map { entry in
                var entry = entry
                let value = SecretPolicy.restore(Workspace(collections: [RequestCollection(name: "History", requests: [entry.request])]), secrets: loadedSecrets)
                entry.request = value.collections[0].requests[0]; return entry
            }
        }
        if testing, let url = ProcessInfo.processInfo.environment["MONKEYTAIL_TEST_URL"] { workspace.collections[0].requests[0].url = url }
        selectedRequestID = workspace.collections.first?.requests.first?.id
        if !testing { restoreTabs() }
        if !testing {
            if let data = try? Data(contentsOf: self.directory.appendingPathComponent("sync-state.json")), let state = try? JSONDecoder().decode(WorkspaceSyncState.self, from: data) { syncState = state }
            if !FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("settings.json").path) { settings.edited = FileManager.default.fileExists(atPath: location.path) }
        }
        settings.useKeychain = keychain
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
    func openTab(_ id: UUID) {
        guard !openRequestIDs.contains(id) else { return }
        openRequestIDs.append(id)
        if openRequestIDs.count > Self.maximumTabs, let oldest = openRequestIDs.first(where: { $0 != id }) { openRequestIDs.removeAll { $0 == oldest } }
    }
    /// Drops tabs whose requests were deleted, replaced, or synced away.
    private func pruneTabs() {
        guard !openRequestIDs.isEmpty else { return }
        let ids = Set(workspace.collections.lazy.flatMap(\.requests).map(\.id))
        if openRequestIDs.contains(where: { !ids.contains($0) }) { openRequestIDs.removeAll { !ids.contains($0) } }
    }
    /// Closes tabs; selection moves to the neighbouring tab, as in Postman.
    func closeTabs(_ ids: Set<UUID>) {
        guard let selected = selectedRequestID, ids.contains(selected), let index = openRequestIDs.firstIndex(of: selected) else { openRequestIDs.removeAll { ids.contains($0) }; return }
        let next = (openRequestIDs[index...].dropFirst() + openRequestIDs[..<index].reversed()).first { !ids.contains($0) && request($0) != nil }
        openRequestIDs.removeAll { ids.contains($0) }
        selectedRequestID = next
    }
    private struct TabState: Codable { var open: [UUID]; var selected: UUID? }
    private func restoreTabs() {
        defer { persistsTabs = true }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("tabs.json")), let state = try? JSONDecoder().decode(TabState.self, from: data) else { return }
        let ids = Set(workspace.collections.lazy.flatMap(\.requests).map(\.id)), open = state.open.filter(ids.contains).suffix(Self.maximumTabs)
        guard !open.isEmpty else { return }
        openRequestIDs = Array(open)
        selectedRequestID = state.selected.flatMap { ids.contains($0) ? $0 : nil } ?? open.last
    }
    private func saveTabs() {
        guard persistsTabs, let data = try? JSONEncoder().encode(TabState(open: openRequestIDs, selected: selectedRequestID)) else { return }
        try? write(data, name: "tabs.json")
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
            try apply(InterchangeImport.decode(text))
        }
    }
    /// Imports several files or a chosen folder, such as a Bruno collection.
    func importFiles(_ files: [ImportFile], name: String) throws {
        guard files.reduce(0, { $0 + $1.text.utf8.count }) <= 40 * 1024 * 1024 else { throw ClientError("Imports must be smaller than 40 MB.") }
        if files.count == 1, let file = files.first, CurlCodec.isCommand(file.text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "") { try importContent(file.text); return }
        try apply(InterchangeImport.decode(files: files, name: name))
    }
    private func apply(_ result: CollectionImport) throws {
        var incoming = result.workspace
        let incomingBytes = incoming.collections.flatMap(\.requests).reduce(0) { $0 + attachmentBytes($1) }
        guard workspaceAttachmentBytes + incomingBytes <= 40 * 1024 * 1024 else { throw ClientError("Workspace attachments exceed 40 MB.") }
        let originalSelected = incoming.selectedEnvironmentID
        var importedSelection: UUID?
        for c in incoming.collections.indices {
            incoming.collections[c].id = UUID()
            let folderIDs = Dictionary((incoming.collections[c].folders ?? []).map { ($0.id, UUID()) }, uniquingKeysWith: { first, _ in first })
            incoming.collections[c].folders = incoming.collections[c].folders.map { $0.map { folder in
                var folder = folder; folder.id = folderIDs[folder.id]!; folder.parentID = folder.parentID.flatMap { folderIDs[$0] }; return folder
            } }
            for r in incoming.collections[c].requests.indices {
                incoming.collections[c].requests[r].id = UUID()
                incoming.collections[c].requests[r].folderID = incoming.collections[c].requests[r].folderID.flatMap { folderIDs[$0] }
            }
        }
        for e in incoming.environments.indices {
            let old = incoming.environments[e].id
            incoming.environments[e].id = UUID()
            if old == originalSelected { importedSelection = incoming.environments[e].id }
        }
        workspace.collections += incoming.collections
        workspace.environments += incoming.environments
        if let globals = incoming.globals, !globals.isEmpty {
            workspace.globals = (workspace.globals ?? []).filter { field in !globals.contains { $0.name == field.name } } + globals
        }
        if result.includesSettings { workspace.proxy = incoming.proxy }
        if let selected = importedSelection ?? incoming.environments.first?.id { workspace.selectedEnvironmentID = selected }
        selectedRequestID = incoming.collections.first?.requests.first?.id ?? selectedRequestID
        let count = incoming.collections.reduce(0) { $0 + $1.requests.count }
        let globalsNote = (incoming.globals ?? []).isEmpty ? "" : " and \(incoming.globals!.count) globals"
        notice = (["Imported \(count) requests and \(incoming.environments.count) environments\(globalsNote)."] + result.warnings).joined(separator: "\n\n")
    }

    func send() {
        guard let saved = selectedRequest, runningID == nil, collectionRun?.running != true, saved.transport != .websocket, saved.transport != .sse else { return }
        runningID = saved.id; errors[saved.id] = nil; untrustedCertificates[saved.id] = nil
        let environmentID = workspace.selectedEnvironmentID
        let proxy = workspace.proxy
        sendTask = Task {
            defer { runningID = nil; sendTask = nil }
            do {
                let execution = try await execute(saved, environmentID: environmentID, proxy: proxy)
                testResults[saved.id] = execution.tests
                guard let response = execution.response else { throw ClientError("A before-request script skipped this request.") }
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
                if let error = error as? UntrustedCertificateError { untrustedCertificates[saved.id] = error.certificate }
                history.insert(HistoryEntry(request: saved, status: nil, duration: 0, error: message), at: 0)
            }
            history = Array(history.prefix(50)).map { entry in
                var entry = entry; entry.request.fileBody?.data = nil
                if entry.request.multipart != nil { for index in entry.request.multipart!.indices { entry.request.multipart![index].file?.data = nil } }
                return entry
            }; persistHistory()
        }
    }
    /// Trusts the rejected certificate for its exact host and port on this device, then resends.
    func trustCertificate(for requestID: UUID) {
        guard let certificate = untrustedCertificates[requestID] else { return }
        do { try network.trust(certificate); untrustedCertificates[requestID] = nil; send() } catch { issue = error.localizedDescription }
    }

    struct RequestExecution {
        /// nil when a before-request script called `pm.execution.skipRequest()`.
        var response: APIResponse?
        var url = ""
        var tests: [AssertionResult] = []
        var scriptError: String?
        var directive: RunnerDirective?
        /// Script variable edits; nil values were unset.
        var changes: [String: String?] = [:]
    }

    /// Sends one saved request with inheritance, scripts, cookies, mocks, and assertions.
    /// `scope` overlays the active environment, as collection-run variables and data rows do.
    func execute(_ saved: APIRequest, environmentID: UUID?, proxy: ProxySettings, scope: [String: String] = [:], context: ScriptContext = ScriptContext()) async throws -> RequestExecution {
        var execution = RequestExecution(), logs: [ScriptLog] = [], context = context
        context.proxy = proxy
        let resolved = try effective(saved, scope: scope)
        var request = resolved.request, variables = resolved.variables
        let initialVariables = variables
        var globalKeys = Set<String>()
        func recordChanges() {
            for (key, value) in variables where initialVariables[key] != value && !globalKeys.contains(key) { execution.changes[key] = value }
            for key in initialVariables.keys where variables[key] == nil && !globalKeys.contains(key) { execution.changes[key] = .some(nil) }
        }
        if request.auth.kind == .oauth2, let oauth = request.auth.oauth, let expires = oauth.expiresAt, expires < Date().addingTimeInterval(30), !oauth.refreshToken.isEmpty {
            request.auth.oauth = try await OAuthAuthorizer().refresh(oauth, proxy: proxy)
            persistAuth(request.auth, for: saved)
        }
        if request.scriptsEnabled && !request.preScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.globals = workspace.globalValues; context.collectionVariables = collectionValues(of: saved.id)
            if request.cookieJarEnabled == true, network.issue == nil, let url = (try? RequestBuilder.resolve(request.url, variables: variables)).flatMap(URL.init(string:)) { context.cookies = network.jar(environmentID).cookies(for: url) }
            let result = try await ScriptRunner().run(request.preScript, request: request, variables: variables, context: context)
            request.method = result.request.method; request.url = result.request.url
            request.headers = result.request.headers.sorted { $0.key < $1.key }.map { Field($0.key, $0.value) }
            if request.body != result.request.body && request.bodyKind == .none { request.bodyKind = .text }
            request.body = result.request.body
            variables = result.variables; logs += result.logs.map { ScriptLog($0.level, $0.message) }
            execution.directive = result.directive
            applyScriptVariables(variables, original: initialVariables, to: environmentID)
            let changedGlobals = applyGlobals(result.globals, original: context.globals).union(applyCollectionVariables(result.collectionVariables, original: context.collectionVariables, request: saved.id))
            if !changedGlobals.isEmpty {
                // Global and collection edits apply to this send unless a higher scope defines the same name.
                let refreshed = try effective(saved, scope: scope).variables
                for key in changedGlobals { variables[key] = refreshed[key] }
                globalKeys.formUnion(changedGlobals)
            }
            variables.merge(result.locals ?? [:]) { _, local in local }
            if result.skip == true { recordChanges(); return execution }
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
        execution.url = built.url?.absoluteString ?? request.url
        var response: APIResponse
        if let mock = request.mock, mock.enabled { response = try await mock.response(url: execution.url) }
        else {
            let protectedHeaders = request.headers.filter(\.isSecret).map(\.name) + (request.auth.apiKey.map { $0.inQuery ? [] : [$0.name] } ?? [])
            let client = HTTPClient(followRedirects: request.followRedirects)
            response = try await client.send(built, proxy: proxy, impersonation: request.impersonation, cookies: jar, tls: network.identity(for: built.url), sensitiveHeaders: protectedHeaders, trusted: network.trustedCertificates)
            if request.auth.kind == .digest, response.status == 401, let challenge = DigestAuth.challenge(from: response.headers), let url = built.url {
                try Task.checkCancellation()
                built.setValue(try DigestAuth.authorization(challenge, username: RequestBuilder.resolve(request.auth.username, variables: variables), password: RequestBuilder.resolve(request.auth.password, variables: variables),
                                                            method: built.httpMethod ?? "GET", uri: DigestAuth.uri(for: url), body: built.httpBody), forHTTPHeaderField: "Authorization")
                response = try await client.send(built, proxy: proxy, impersonation: request.impersonation, cookies: jar, tls: network.identity(for: built.url), sensitiveHeaders: protectedHeaders, trusted: network.trustedCertificates)
            }
        }
        if cookiesEnabled, let received = response.sessionCookies { var jar = CookieJar(); jar.cookies = received; try network.setJar(jar, environment: environmentID) }
        let assertionResults = await Task.detached { [request, response] in ResponseTests.evaluate(request.assertions ?? [], response: response, schema: request.responseSchema) }.value
        execution.tests = assertionResults
        logs += assertionResults.map { ScriptLog($0.passed ? "pass" : "fail", $0.name + ": " + $0.message) }
        if request.scriptsEnabled && !request.postScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                context.globals = workspace.globalValues; context.collectionVariables = collectionValues(of: saved.id)
                if let url = built.url {
                    var visible = CookieJar()
                    if cookiesEnabled { visible.cookies = response.sessionCookies ?? jar?.cookies ?? [] } else { visible.capture(headers: response.headers, url: url) }
                    context.cookies = visible.cookies(for: url)
                }
                let result = try await ScriptRunner().run(request.postScript, request: request, response: response, variables: variables, context: context)
                logs += result.logs.map { ScriptLog($0.level, $0.message) }
                applyScriptVariables(result.variables, original: variables, to: environmentID)
                applyGlobals(result.globals, original: context.globals)
                applyCollectionVariables(result.collectionVariables, original: context.collectionVariables, request: saved.id)
                variables = result.variables.merging(result.locals ?? [:]) { _, local in local }
                execution.directive = result.directive ?? execution.directive
            } catch {
                if Task.isCancelled { throw CancellationError() }
                logs.append(ScriptLog("error", error.localizedDescription))
                execution.scriptError = error.localizedDescription
            }
        }
        response.logs = logs
        execution.response = response
        recordChanges()
        return execution
    }
    func effective(_ request: APIRequest, scope: [String: String] = [:]) throws -> ResolvedRequest {
        try RequestInheritance.resolve(request, collection: workspace.collections.first { $0.requests.contains { $0.id == request.id } },
                                       environment: variables.merging(scope) { _, overlay in overlay }, globals: workspace.globalValues)
    }
    /// Values that `{{variables}}` resolve to for this request, and which names are sensitive.
    func variableHints(for request: APIRequest) -> VariableHintContext {
        let collection = workspace.collections.first { $0.requests.contains { $0.id == request.id } }
        let fields = (workspace.globals ?? []) + (environment?.variables ?? []) + (collection?.defaults?.variables ?? []) + (collection?.folders ?? []).flatMap(\.defaults.variables) + (request.variables ?? [])
        return VariableHintContext(values: (try? effective(request).variables) ?? variables, secrets: Set(fields.filter(\.isSecret).map(\.name)))
    }
    /// Applies script edits to globals and returns the changed names.
    @discardableResult private func applyGlobals(_ values: [String: String]?, original: [String: String]) -> Set<String> {
        var fields = workspace.globals ?? []
        let changed = Self.apply(values, original: original, to: &fields)
        if !changed.isEmpty { workspace.globals = fields }
        return changed
    }
    private func collectionValues(of requestID: UUID) -> [String: String] {
        (workspace.collections.first { $0.requests.contains { $0.id == requestID } }?.defaults?.variables ?? []).filter { $0.enabled && !$0.name.isEmpty }.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
    /// Applies `pm.collectionVariables` edits to the request's collection and returns the changed names.
    @discardableResult private func applyCollectionVariables(_ values: [String: String]?, original: [String: String], request requestID: UUID) -> Set<String> {
        guard let c = workspace.collections.firstIndex(where: { $0.requests.contains { $0.id == requestID } }) else { return [] }
        var fields = workspace.collections[c].defaults?.variables ?? []
        let changed = Self.apply(values, original: original, to: &fields)
        if !changed.isEmpty {
            if workspace.collections[c].defaults == nil { workspace.collections[c].defaults = RequestDefaults() }
            workspace.collections[c].defaults?.variables = fields
        }
        return changed
    }
    private static func apply(_ values: [String: String]?, original: [String: String], to fields: inout [Field]) -> Set<String> {
        guard let values, values != original else { return [] }
        var changed = Set<String>()
        for (key, value) in values where original[key] != value {
            changed.insert(key)
            if let index = fields.firstIndex(where: { $0.name == key }) { fields[index].value = value; fields[index].enabled = true } else { fields.append(Field(key, value)) }
        }
        for key in original.keys where values[key] == nil { changed.insert(key); fields.removeAll { $0.name == key } }
        return changed
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
        if !useKeychain {
            return WorkspacePersistence.Snapshot(workspace: workspace, history: history, sync: syncState,
                settings: try JSONEncoder().encode(settings), secrets: [:], directory: directory)
        }
        var secrets: [String: String] = [:]
        let protectedHistory = history.map { entry in
            var copy = entry
            let value = SecretPolicy.strip(Workspace(collections: [RequestCollection(name: "History", requests: [entry.request])]), secrets: &secrets, files: false)
            copy.request = value.collections[0].requests[0]; return copy
        }
        // Current credentials take precedence over older history definitions.
        let protected = SecretPolicy.strip(workspace, secrets: &secrets, files: false)
        return WorkspacePersistence.Snapshot(workspace: protected, history: protectedHistory, sync: syncState,
            settings: try JSONEncoder().encode(settings), secrets: secrets, directory: directory, useKeychain: true)
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
        do { try syncState.capture(workspace, includeCredentials: syncCredentials) } catch { issue = error.localizedDescription }
    }
    func setUseKeychain(_ enabled: Bool) {
        guard enabled != useKeychain, !vaultUnavailable else { return }
        saveTask?.cancel()
        let previous = vault, old = useKeychain, oldLegacy = settings.legacyKeychain
        do {
            if enabled, settings.legacyKeychain == true {
                var previousValues = try SecretVault(directory: directory, useKeychain: true).load()
                var currentValues: [String: String] = [:]
                _ = SecretPolicy.strip(workspace, secrets: &currentValues, files: false)
                previousValues.merge(currentValues.filter { !$0.value.isEmpty }) { _, current in current }
                applyingSync = true
                workspace = SecretPolicy.restore(workspace, secrets: previousValues)
                applyingSync = false
            }
            try network.setUseKeychain(enabled)
#if os(iOS)
            if managesWatchStorage { try WatchCompanionLink.shared.setUseKeychain(enabled) }
#endif
            settings.useKeychain = enabled
            settings.legacyKeychain = false
            try persistence.save(persistenceSnapshot())
            vault = SecretVault(directory: directory, useKeychain: enabled)
            do { try previous.remove() } catch { issue = error.localizedDescription }
        } catch { settings.useKeychain = old; settings.legacyKeychain = oldLegacy; issue = error.localizedDescription }
    }
    func setSyncCredentials(_ enabled: Bool) {
        settings.syncCredentials = enabled
        do { try syncState.capture(workspace, includeCredentials: enabled); save() }
        catch { issue = error.localizedDescription }
    }
    func setHideCredentials(_ enabled: Bool) { settings.hideCredentials = enabled; save() }
    func setWatchIncludesCredentials(_ enabled: Bool) { settings.watchIncludesCredentials = enabled; save() }
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
            if settings.edited || remote.isEmpty { try syncState.capture(workspace, includeCredentials: syncCredentials) }
            for state in remote { syncState.merge(state) }
            let merged = try syncState.workspace(local: workspace, includeCredentials: syncCredentials)
            // Reapply this device's sharing choice after merging other devices' records.
            try syncState.capture(merged, includeCredentials: syncCredentials)
            if merged != workspace {
                var ignored: [String: String] = [:]
                let recovery = useKeychain ? SecretPolicy.strip(workspace, secrets: &ignored, files: false) : workspace
                try write(JSONEncoder().encode(recovery), name: "workspace-before-sync.json")
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

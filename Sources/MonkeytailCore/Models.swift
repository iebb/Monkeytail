import Foundation

public struct Field: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String
    public var enabled: Bool
    /// Set by the user or an import. Nothing is marked by default, so values stay visible and sync.
    public var secret: Bool?
    public var isSecret: Bool { secret == true }
    /// What opt-in protection (Keychain, excluding credentials from sync or Watch, hidden client code) treats as a credential: the explicit mark, otherwise the sensitive-name heuristic.
    public var isCredential: Bool { secret ?? SecretPolicy.isSensitive(name) }
    public init(_ name: String = "", _ value: String = "", enabled: Bool = true) {
        self.name = name; self.value = value; self.enabled = enabled
    }
}

public enum BodyKind: String, Codable, CaseIterable, Sendable { case none = "None", json = "JSON", text = "Text", form = "Form", multipart = "Multipart", file = "File" }
public enum AuthKind: String, Codable, CaseIterable, Sendable { case none = "None", inherit = "Inherit", bearer = "Bearer", basic = "Basic", digest = "Digest", apiKey = "API key", oauth1 = "OAuth 1.0", oauth2 = "OAuth 2.0", jwt = "JWT Bearer", aws = "AWS SigV4" }
public struct RequestAuth: Codable, Equatable, Sendable {
    public var kind: AuthKind = .none
    public var token = ""
    public var username = ""
    public var password = ""
    public var apiKey: APIKeyAuth?
    public var oauth: OAuthConfiguration?
    public var oauth1: OAuth1Auth?
    public var jwt: JWTAuth?
    public var aws: AWSAuth?
    public init() {}
}

public struct APIRequest: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "Untitled request"
    public var method = "GET"
    public var url = "https://httpbin.org/get"
    public var headers: [Field] = [Field("Accept", "application/json")]
    public var query: [Field] = []
    /// Values for `:name` URL path segments, as in Postman.
    public var pathVariables: [Field]?
    public var bodyKind: BodyKind = .none
    public var body = ""
    public var form: [Field] = []
    public var multipart: [MultipartPart]?
    public var fileBody: RequestFile?
    public var auth = RequestAuth()
    public var preScript = ""
    public var postScript = ""
    public var scriptsEnabled = true
    public var followRedirects = true
    public var timeout: Double = 30
    public var impersonation: BrowserImpersonation?
    public var folderID: UUID?
    public var variables: [Field]?
    public var transport: RequestTransport?
    public var graphql: GraphQLRequest?
    public var assertions: [ResponseAssertion]?
    public var requestSchema: String?
    public var responseSchema: String?
    public var parameterHints: [ParameterHint]?
    public var cookieJarEnabled: Bool?
    public var mock: MockResponse?
    public var favorite: Bool?
    /// Markdown documentation, as in Postman request descriptions.
    public var description: String?
    /// Saved responses, as in Postman examples.
    public var examples: [ResponseExample]?
    public init(name: String = "Untitled request", method: String = "GET", url: String = "https://httpbin.org/get") {
        self.name = name; self.method = method; self.url = url
    }
}

public struct RequestCollection: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var requests: [APIRequest]
    public var folders: [RequestFolder]?
    public var defaults: RequestDefaults?
    /// The workspace this collection belongs to; nil is the default workspace.
    public var workspaceID: UUID?
    public init(name: String, requests: [APIRequest] = []) { self.name = name; self.requests = requests }
}

public struct APIEnvironment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var variables: [Field]
    /// The workspace this environment belongs to; nil is the default workspace.
    public var workspaceID: UUID?
    public init(name: String, variables: [Field] = []) { self.name = name; self.variables = variables }
    public var values: [String: String] {
        variables.filter { $0.enabled && !$0.name.isEmpty }.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
}

public enum ProxyKind: String, CaseIterable, Codable, Sendable { case system = "System", http = "HTTP CONNECT", https = "HTTPS CONNECT", socks = "SOCKS5" }
public struct ProxySettings: Codable, Equatable, Sendable {
    public var kind: ProxyKind = .system
    public var host = ""
    public var port = "8080"
    public var username = ""
    public var password = ""
    public init() {}
}

public struct ScriptLog: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var level: String
    public var message: String
    public init(_ level: String, _ message: String) { self.level = level; self.message = message }
}

public struct APIResponse: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var status: Int
    public var headers: [Field]
    public var body: Data
    public var duration: Double
    public var url: String
    public var receivedAt = Date()
    public var logs: [ScriptLog] = []
    public var diagnostics: RequestDiagnostics?
    public var sessionCookies: [StoredCookie]?
    public var text: String { String(data: body, encoding: .utf8) ?? String(data: body, encoding: .isoLatin1) ?? "Binary response (\(body.count) bytes)" }
    public init(status: Int, headers: [Field], body: Data, duration: Double, url: String) {
        self.status = status; self.headers = headers; self.body = body; self.duration = duration; self.url = url
    }
}

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public var request: APIRequest
    public var status: Int?
    public var duration: Double
    public var date = Date()
    public var error: String?
    public init(request: APIRequest, status: Int?, duration: Double, error: String? = nil) {
        self.request = request; self.status = status; self.duration = duration; self.error = error
    }
}

public struct Workspace: Codable, Equatable, Sendable {
    public var version = 1
    public var collections: [RequestCollection]
    public var environments: [APIEnvironment]
    public var selectedEnvironmentID: UUID?
    /// Postman-style globals: available in every environment at the lowest precedence.
    public var globals: [Field]?
    public var proxy = ProxySettings()
    /// Workspaces besides the default one, and the default's name once renamed. Collections and environments refer to them by ID.
    public var workspaces: [WorkspaceInfo]?
    /// This device's environment choice for each workspace other than the default, keyed by workspace ID.
    public var selectedEnvironmentIDs: [String: UUID]?
    public init(collections: [RequestCollection] = [], environments: [APIEnvironment] = []) {
        self.collections = collections; self.environments = environments
    }
    public var globalValues: [String: String] {
        (globals ?? []).filter { $0.enabled && !$0.name.isEmpty }.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
    public static var starter: Workspace {
        let echo = APIRequest(name: "Echo a request", url: "{{base_url}}/get")
        var create = APIRequest(name: "Send some JSON", method: "POST", url: "{{base_url}}/post")
        create.bodyKind = .json
        create.body = "{\n  \"hello\": \"world\",\n  \"from\": \"Monkeytail\"\n}"
        create.postScript = "test('Request succeeded', () => {\n  assert(response.status === 200, 'Expected HTTP 200');\n});\nconsole.log(response.json());"
        let health = APIRequest(name: "Check a status", url: "{{base_url}}/status/200")
        let environment = APIEnvironment(name: "Playground", variables: [Field("base_url", "https://httpbin.org")])
        var workspace = Workspace(collections: [RequestCollection(name: "Getting started", requests: [echo, create, health])], environments: [environment])
        workspace.selectedEnvironmentID = environment.id
        return workspace
    }
}

/// A Postman-style workspace: its own collections, environments and globals.
public struct WorkspaceInfo: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    /// Globals for this workspace. The default workspace keeps its globals in `Workspace.globals`.
    public var globals: [Field]?
    public init(id: UUID = UUID(), name: String, globals: [Field]? = nil) { self.id = id; self.name = name; self.globals = globals }
}

extension Workspace {
    /// Holds everything saved before workspaces existed. Its name is empty until renamed.
    public static let defaultWorkspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    /// Every workspace, default first.
    public var workspaceList: [WorkspaceInfo] {
        let stored = workspaces ?? []
        return [stored.first { $0.id == Self.defaultWorkspaceID } ?? WorkspaceInfo(id: Self.defaultWorkspaceID, name: "")] + stored.filter { $0.id != Self.defaultWorkspaceID }
    }
    /// The owning workspace; items whose workspace no longer exists fall back to the default.
    public func workspaceID(_ id: UUID?) -> UUID {
        guard let id, id != Self.defaultWorkspaceID, workspaces?.contains(where: { $0.id == id }) == true else { return Self.defaultWorkspaceID }
        return id
    }
    public func workspaceID(ofRequest id: UUID?) -> UUID { workspaceID(collections.first { $0.requests.contains { $0.id == id } }?.workspaceID) }
    public func collections(in workspace: UUID) -> [RequestCollection] { collections.filter { workspaceID($0.workspaceID) == workspace } }
    public func environments(in workspace: UUID) -> [APIEnvironment] { environments.filter { workspaceID($0.workspaceID) == workspace } }
    public func globals(in workspace: UUID) -> [Field] {
        workspace == Self.defaultWorkspaceID ? globals ?? [] : workspaces?.first { $0.id == workspace }?.globals ?? []
    }
    public func globalValues(in workspace: UUID) -> [String: String] {
        globals(in: workspace).filter { $0.enabled && !$0.name.isEmpty }.reduce(into: [:]) { $0[$1.name] = $1.value }
    }
    public mutating func setGlobals(_ fields: [Field], in workspace: UUID) {
        if workspace == Self.defaultWorkspaceID { globals = fields.isEmpty && globals == nil ? nil : fields }
        else if let index = workspaces?.firstIndex(where: { $0.id == workspace }) { workspaces![index].globals = fields.isEmpty ? nil : fields }
    }
    public func selectedEnvironmentID(in workspace: UUID) -> UUID? {
        let id = workspace == Self.defaultWorkspaceID ? selectedEnvironmentID : selectedEnvironmentIDs?[workspace.uuidString]
        return environments(in: workspace).contains { $0.id == id } ? id : nil
    }
    public mutating func selectEnvironment(_ id: UUID?, in workspace: UUID) {
        if workspace == Self.defaultWorkspaceID { selectedEnvironmentID = id }
        else { var map = selectedEnvironmentIDs ?? [:]; map[workspace.uuidString] = id; selectedEnvironmentIDs = map }
    }
    /// Removes a workspace with its collections and environments. The default workspace can only be emptied.
    public mutating func removeWorkspace(_ id: UUID) {
        guard id != Self.defaultWorkspaceID else { return }
        let owner = self
        collections.removeAll { owner.workspaceID($0.workspaceID) == id }
        environments.removeAll { owner.workspaceID($0.workspaceID) == id }
        workspaces?.removeAll { $0.id == id }
        selectedEnvironmentIDs?[id.uuidString] = nil
    }
}

public struct ClientError: LocalizedError, Equatable, Sendable {
    public var message: String
    public var errorDescription: String? { message }
    public init(_ message: String.LocalizationValue) { self.message = String(localized: message, bundle: .module) }
    public init(verbatim message: String) { self.message = message }
    @_disfavoredOverload public init(_ message: String) { self.message = message }
}

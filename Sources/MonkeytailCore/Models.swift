import Foundation

public struct Field: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String
    public var enabled: Bool
    public init(_ name: String = "", _ value: String = "", enabled: Bool = true) {
        self.name = name; self.value = value; self.enabled = enabled
    }
}

public enum BodyKind: String, Codable, CaseIterable, Sendable { case none = "None", json = "JSON", text = "Text", form = "Form" }
public enum AuthKind: String, Codable, CaseIterable, Sendable { case none = "None", bearer = "Bearer", basic = "Basic" }
public struct RequestAuth: Codable, Equatable, Sendable {
    public var kind: AuthKind = .none
    public var token = ""
    public var username = ""
    public var password = ""
    public init() {}
}

public struct APIRequest: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name = "Untitled request"
    public var method = "GET"
    public var url = "https://httpbin.org/get"
    public var headers: [Field] = [Field("Accept", "application/json")]
    public var query: [Field] = []
    public var bodyKind: BodyKind = .none
    public var body = ""
    public var form: [Field] = []
    public var auth = RequestAuth()
    public var preScript = ""
    public var postScript = ""
    // Imported scripts remain opt-in; importing never executes code or sends a request.
    public var scriptsEnabled = false
    public var followRedirects = true
    public var timeout: Double = 30
    public init(name: String = "Untitled request", method: String = "GET", url: String = "https://httpbin.org/get") {
        self.name = name; self.method = method; self.url = url
    }
}

public struct RequestCollection: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var requests: [APIRequest]
    public init(name: String, requests: [APIRequest] = []) { self.name = name; self.requests = requests }
}

public struct APIEnvironment: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var variables: [Field]
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
    public var proxy = ProxySettings()
    public init(collections: [RequestCollection] = [], environments: [APIEnvironment] = []) {
        self.collections = collections; self.environments = environments
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

public struct ClientError: LocalizedError, Equatable, Sendable {
    public var message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

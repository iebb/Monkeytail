import Foundation

public struct APIKeyAuth: Codable, Equatable, Sendable {
    public var name = "X-API-Key", value = ""
    public var inQuery = false
    public init() {}
}
public struct AWSAuth: Codable, Equatable, Sendable {
    public var accessKey = "", secretKey = "", sessionToken = "", region = "us-east-1", service = "execute-api"
    public init() {}
}
public enum OAuthGrant: String, Codable, CaseIterable, Sendable { case pkce = "Authorization code + PKCE", clientCredentials = "Client credentials" }
public struct OAuthConfiguration: Codable, Equatable, Sendable {
    public var grant: OAuthGrant = .pkce
    public var authorizationURL = "", tokenURL = "", clientID = "", clientSecret = "", scope = ""
    public var callbackURL = "monkeytail://oauth", accessToken = "", refreshToken = ""
    public var expiresAt: Date?
    public init() {}
}
public enum RequestTransport: String, Codable, CaseIterable, Sendable { case http = "HTTP", graphql = "GraphQL", websocket = "WebSocket", sse = "SSE" }
public struct GraphQLRequest: Codable, Equatable, Sendable {
    public var query = "query { __typename }", variables = "{}", operationName = ""
    public init() {}
    public func body(values: [String: String]) throws -> Data {
        let resolved = try RequestBuilder.resolve(variables, variables: values)
        guard let object = try JSONSerialization.jsonObject(with: Data(resolved.utf8)) as? [String: Any] else { throw ClientError("GraphQL variables must be a JSON object.") }
        var body: [String: Any] = ["query": try RequestBuilder.resolve(query, variables: values), "variables": object]
        if !operationName.isEmpty { body["operationName"] = operationName }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}
public struct ParameterHint: Codable, Identifiable, Equatable, Sendable {
    public var name: String, location: String, description: String, type: String
    public var required: Bool
    public var id: String { location + "." + name }
    public init(name: String, location: String, description: String = "", type: String = "string", required: Bool = false) {
        self.name = name; self.location = location; self.description = description; self.type = type; self.required = required
    }
}
public struct RequestDefaults: Codable, Equatable, Sendable {
    public var headers: [Field] = [], variables: [Field] = []
    public var auth = RequestAuth()
    public var preScript = "", postScript = ""
    public var scriptsEnabled = false
    public init() {}
}
public struct RequestFolder: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var parentID: UUID?
    public var defaults = RequestDefaults()
    public init(name: String, parentID: UUID? = nil) { self.name = name; self.parentID = parentID; defaults.auth.kind = .inherit }
}
public struct ResolvedRequest: Sendable {
    public var request: APIRequest
    public var variables: [String: String]
}
public enum RequestInheritance {
    public static func resolve(_ request: APIRequest, collection: RequestCollection?, environment: [String: String]) throws -> ResolvedRequest {
        var levels: [RequestDefaults] = []
        if let defaults = collection?.defaults { levels.append(defaults) }
        var ancestors: [RequestFolder] = [], visited = Set<UUID>(), current = request.folderID
        while let id = current {
            guard visited.insert(id).inserted, ancestors.count < 32 else { throw ClientError("Folder hierarchy contains a cycle or is too deep.") }
            guard let folder = collection?.folders?.first(where: { $0.id == id }) else { throw ClientError("Request folder is missing.") }
            ancestors.append(folder); current = folder.parentID
        }
        levels += ancestors.reversed().map(\.defaults)
        var result = request, variables: [String: String] = [:], headers: [Field] = [], inheritedAuth = RequestAuth()
        for level in levels {
            for field in level.variables where field.enabled { variables[field.name] = field.value }
            merge(level.headers, into: &headers)
            if level.auth.kind != .inherit { inheritedAuth = level.auth }
        }
        variables.merge(environment, uniquingKeysWith: { _, new in new })
        for field in request.variables ?? [] where field.enabled { variables[field.name] = field.value }
        merge(request.headers, into: &headers); result.headers = headers
        if request.auth.kind == .inherit { result.auth = inheritedAuth }
        let before = levels.filter(\.scriptsEnabled).map(\.preScript).filter { !$0.isEmpty }
        let after = levels.filter(\.scriptsEnabled).map(\.postScript).filter { !$0.isEmpty }
        result.preScript = (before + (request.scriptsEnabled ? [request.preScript] : [])).joined(separator: "\n")
        result.postScript = (after + (request.scriptsEnabled ? [request.postScript] : [])).joined(separator: "\n")
        result.scriptsEnabled = request.scriptsEnabled || levels.contains(where: \.scriptsEnabled)
        return ResolvedRequest(request: result, variables: variables)
    }
    private static func merge(_ incoming: [Field], into fields: inout [Field]) {
        for field in incoming {
            fields.removeAll { $0.name.caseInsensitiveCompare(field.name) == .orderedSame }
            // Disabled child headers intentionally suppress inherited values.
            fields.append(field)
        }
    }
}
public enum AssertionKind: String, Codable, CaseIterable, Sendable { case status = "Status", duration = "Response time", header = "Header", json = "JSON value", schema = "JSON schema" }
public struct ResponseAssertion: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: AssertionKind = .status
    public var name = "Status is 200", path = "", expected = "200"
    public var enabled = true
    public init() {}
}
public struct AssertionResult: Identifiable, Equatable, Sendable {
    public var id: UUID, name: String, passed: Bool, message: String
}
public struct MockResponse: Codable, Equatable, Sendable {
    public var enabled = false
    public var status = 200, delayMilliseconds = 0
    public var headers: [Field] = [Field("Content-Type", "application/json")]
    public var body = "{\"mock\":true}"
    public var simulatedError: String?
    public init() {}
    public func response(url: String) async throws -> APIResponse {
        guard (100...599).contains(status), (0...30000).contains(delayMilliseconds), body.utf8.count <= 2 * 1024 * 1024 else { throw ClientError("Invalid mock status, delay, or body size.") }
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        try Task.checkCancellation()
        if let error = simulatedError, !error.isEmpty { throw ClientError(error) }
        var response = APIResponse(status: status, headers: headers, body: Data(body.utf8), duration: Double(delayMilliseconds) / 1000, url: url)
        response.diagnostics = RequestDiagnostics(transport: "Offline mock", transactions: [])
        return response
    }
}

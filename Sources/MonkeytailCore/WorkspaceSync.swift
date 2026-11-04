import Foundation

public enum SecretPolicy {
    public static func isSensitive(_ name: String) -> Bool {
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: "_")
        return ["authorization", "cookie", "set_cookie", "proxy_authorization"].contains(normalized)
            || ["token", "secret", "password", "api_key", "apikey", "credential"].contains { normalized.contains($0) }
    }
    /// Removes credential values, leaving stable keys so each device can restore its own secrets.
    public static func strip(_ source: Workspace, secrets: inout [String: String], files: Bool, credentials: Bool = true) -> Workspace {
        var copy = source
        func clean(_ fields: [Field], scope: String) -> [Field] {
            fields.map { field in
                var field = field
                if credentials && field.isSecret { secrets["\(scope).field.\(field.id)"] = field.value; field.value = ""; field.secret = true }
                return field
            }
        }
        for c in copy.collections.indices {
            func cleanDefaults(_ value: RequestDefaults, scope: String) -> RequestDefaults {
                var value = value
                value.headers = clean(value.headers, scope: scope + ".headers"); value.variables = clean(value.variables, scope: scope + ".variables")
                if credentials { stripAllAuth(&value.auth, scope: scope + ".auth", secrets: &secrets) }
                return value
            }
            let scope = "collection.\(copy.collections[c].id)"
            copy.collections[c].defaults = copy.collections[c].defaults.map { cleanDefaults($0, scope: scope) }
            copy.collections[c].folders = copy.collections[c].folders.map { $0.map { folder in var folder = folder; folder.defaults = cleanDefaults(folder.defaults, scope: "folder.\(folder.id)"); return folder } }
            for r in copy.collections[c].requests.indices {
                var request = copy.collections[c].requests[r]
                request.headers = clean(request.headers, scope: "request.\(request.id).headers"); request.query = clean(request.query, scope: "request.\(request.id).query"); request.form = clean(request.form, scope: "request.\(request.id).form")
                if credentials, var url = URLComponents(string: request.url) {
                    var changed = false
                    if let user = url.user { secrets["url.\(request.id).user"] = user; url.user = ""; changed = true }
                    if let password = url.password { secrets["url.\(request.id).password"] = password; url.password = ""; changed = true }
                    if var query = url.percentEncodedQueryItems {
                        for index in query.indices where SecretPolicy.isSensitive(query[index].name.removingPercentEncoding ?? query[index].name) {
                            secrets["url.\(request.id).query.\(query[index].name).\(index)"] = query[index].value ?? ""
                            query[index].value = ""; changed = true
                        }
                        url.percentEncodedQueryItems = query
                    }
                    if changed { request.url = url.string ?? request.url }
                }
                if credentials {
                secrets["auth.\(request.id).token"] = request.auth.token
                secrets["auth.\(request.id).password"] = request.auth.password
                secrets["auth.\(request.id).username"] = request.auth.username
                request.auth.token = ""; request.auth.password = ""; request.auth.username = ""
                stripAdvancedAuth(&request.auth, scope: "auth.\(request.id)", secrets: &secrets)
                }
                request.variables = request.variables.map { clean($0, scope: "request.\(request.id).variables") }
                if credentials, request.multipart != nil {
                    for index in request.multipart!.indices where SecretPolicy.isSensitive(request.multipart![index].name) {
                        secrets["request.\(request.id).part.\(request.multipart![index].id)"] = request.multipart![index].value
                        request.multipart![index].value = ""
                    }
                }
                if files {
                    request.fileBody?.data = nil
                    if request.multipart != nil {
                        for index in request.multipart!.indices {
                            request.multipart![index].file?.data = nil
                            if credentials && SecretPolicy.isSensitive(request.multipart![index].name) { request.multipart![index].value = "" }
                        }
                    }
                }
                copy.collections[c].requests[r] = request
            }
        }
        for e in copy.environments.indices { copy.environments[e].variables = clean(copy.environments[e].variables, scope: "environment.\(copy.environments[e].id)") }
        copy.globals = copy.globals.map { clean($0, scope: "globals") }
        if credentials {
        secrets["proxy.password"] = copy.proxy.password; secrets["proxy.username"] = copy.proxy.username; copy.proxy.password = ""; copy.proxy.username = ""
        }
        return copy
    }
    public static func restore(_ source: Workspace, secrets: [String: String], local: Workspace? = nil, credentials: Bool = true) -> Workspace {
        var copy = source
        func restoreFields(_ fields: [Field], scope: String) -> [Field] {
            fields.map { field in
                var field = field
                if field.isSecret { field.value = secrets["\(scope).field.\(field.id)"] ?? field.value }
                return field
            }
        }
        let localRequests = Dictionary((local?.collections.flatMap(\.requests) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for c in copy.collections.indices {
            func restoreDefaults(_ value: RequestDefaults, scope: String) -> RequestDefaults {
                var value = value
                value.headers = restoreFields(value.headers, scope: scope + ".headers"); value.variables = restoreFields(value.variables, scope: scope + ".variables")
                restoreAllAuth(&value.auth, scope: scope + ".auth", secrets: secrets); return value
            }
            let scope = "collection.\(copy.collections[c].id)"
            copy.collections[c].defaults = copy.collections[c].defaults.map { restoreDefaults($0, scope: scope) }
            copy.collections[c].folders = copy.collections[c].folders.map { $0.map { folder in var folder = folder; folder.defaults = restoreDefaults(folder.defaults, scope: "folder.\(folder.id)"); return folder } }
            for r in copy.collections[c].requests.indices {
                var request = copy.collections[c].requests[r]
                request.headers = restoreFields(request.headers, scope: "request.\(request.id).headers"); request.query = restoreFields(request.query, scope: "request.\(request.id).query"); request.form = restoreFields(request.form, scope: "request.\(request.id).form")
                if var url = URLComponents(string: request.url) {
                    var changed = false
                    if url.user != nil { url.user = secrets["url.\(request.id).user"] ?? url.user; changed = true }
                    if url.password != nil { url.password = secrets["url.\(request.id).password"] ?? url.password; changed = true }
                    if var query = url.percentEncodedQueryItems {
                        for index in query.indices where SecretPolicy.isSensitive(query[index].name.removingPercentEncoding ?? query[index].name) { query[index].value = secrets["url.\(request.id).query.\(query[index].name).\(index)"] ?? query[index].value; changed = true }
                        url.percentEncodedQueryItems = query
                    }
                    if changed { request.url = url.string ?? request.url }
                }
                request.auth.token = secrets["auth.\(request.id).token"] ?? request.auth.token
                request.auth.password = secrets["auth.\(request.id).password"] ?? request.auth.password
                request.auth.username = secrets["auth.\(request.id).username"] ?? request.auth.username
                restoreAdvancedAuth(&request.auth, scope: "auth.\(request.id)", secrets: secrets)
                request.variables = request.variables.map { restoreFields($0, scope: "request.\(request.id).variables") }
                if request.multipart != nil {
                    for index in request.multipart!.indices where SecretPolicy.isSensitive(request.multipart![index].name) {
                        request.multipart![index].value = secrets["request.\(request.id).part.\(request.multipart![index].id)"] ?? request.multipart![index].value
                    }
                }
                if let previous = localRequests[request.id] {
                    if request.fileBody?.filename == previous.fileBody?.filename { request.fileBody?.data = previous.fileBody?.data }
                    if request.multipart != nil {
                        for i in request.multipart!.indices {
                            if let part = previous.multipart?.first(where: { $0.id == request.multipart![i].id }) {
                                if part.file?.filename == request.multipart![i].file?.filename { request.multipart![i].file?.data = part.file?.data }
                                if credentials && SecretPolicy.isSensitive(part.name) { request.multipart![i].value = part.value }
                            }
                        }
                    }
                }
                copy.collections[c].requests[r] = request
            }
        }
        for e in copy.environments.indices { copy.environments[e].variables = restoreFields(copy.environments[e].variables, scope: "environment.\(copy.environments[e].id)") }
        copy.globals = copy.globals.map { restoreFields($0, scope: "globals") }
        copy.proxy.password = secrets["proxy.password"] ?? copy.proxy.password
        copy.proxy.username = secrets["proxy.username"] ?? copy.proxy.username
        return copy
    }
    private static func stripAdvancedAuth(_ auth: inout RequestAuth, scope: String, secrets: inout [String: String]) {
        if var key = auth.apiKey { secrets[scope + ".apiKey"] = key.value; key.value = ""; auth.apiKey = key }
        if var oauth = auth.oauth {
            secrets[scope + ".clientSecret"] = oauth.clientSecret; secrets[scope + ".accessToken"] = oauth.accessToken; secrets[scope + ".refreshToken"] = oauth.refreshToken; secrets[scope + ".oauthPassword"] = oauth.password
            if let expires = oauth.expiresAt { secrets[scope + ".expires"] = String(expires.timeIntervalSince1970) }; oauth.clientSecret = ""; oauth.accessToken = ""; oauth.refreshToken = ""; oauth.password = oauth.password.map { _ in "" }; oauth.expiresAt = nil; auth.oauth = oauth
        }
        if var aws = auth.aws {
            secrets[scope + ".awsAccess"] = aws.accessKey; secrets[scope + ".awsSecret"] = aws.secretKey; secrets[scope + ".awsSession"] = aws.sessionToken
            aws.accessKey = ""; aws.secretKey = ""; aws.sessionToken = ""; auth.aws = aws
        }
        if var oauth1 = auth.oauth1 {
            secrets[scope + ".oauth1Consumer"] = oauth1.consumerSecret; secrets[scope + ".oauth1Token"] = oauth1.token; secrets[scope + ".oauth1TokenSecret"] = oauth1.tokenSecret
            oauth1.consumerSecret = ""; oauth1.token = ""; oauth1.tokenSecret = ""; auth.oauth1 = oauth1
        }
        if var jwt = auth.jwt {
            secrets[scope + ".jwtSecret"] = jwt.secret; secrets[scope + ".jwtKey"] = jwt.privateKey
            jwt.secret = ""; jwt.privateKey = ""; auth.jwt = jwt
        }
    }
    private static func restoreAdvancedAuth(_ auth: inout RequestAuth, scope: String, secrets: [String: String]) {
        if var key = auth.apiKey { key.value = secrets[scope + ".apiKey"] ?? key.value; auth.apiKey = key }
        if var oauth = auth.oauth {
            oauth.clientSecret = secrets[scope + ".clientSecret"] ?? oauth.clientSecret; oauth.accessToken = secrets[scope + ".accessToken"] ?? oauth.accessToken; oauth.refreshToken = secrets[scope + ".refreshToken"] ?? oauth.refreshToken; oauth.password = secrets[scope + ".oauthPassword"] ?? oauth.password; if let value = secrets[scope + ".expires"], let seconds = Double(value) { oauth.expiresAt = Date(timeIntervalSince1970: seconds) }; auth.oauth = oauth
        }
        if var aws = auth.aws {
            aws.accessKey = secrets[scope + ".awsAccess"] ?? aws.accessKey; aws.secretKey = secrets[scope + ".awsSecret"] ?? aws.secretKey; aws.sessionToken = secrets[scope + ".awsSession"] ?? aws.sessionToken; auth.aws = aws
        }
        if var oauth1 = auth.oauth1 {
            oauth1.consumerSecret = secrets[scope + ".oauth1Consumer"] ?? oauth1.consumerSecret; oauth1.token = secrets[scope + ".oauth1Token"] ?? oauth1.token; oauth1.tokenSecret = secrets[scope + ".oauth1TokenSecret"] ?? oauth1.tokenSecret; auth.oauth1 = oauth1
        }
        if var jwt = auth.jwt {
            jwt.secret = secrets[scope + ".jwtSecret"] ?? jwt.secret; jwt.privateKey = secrets[scope + ".jwtKey"] ?? jwt.privateKey; auth.jwt = jwt
        }
    }
    private static func stripAllAuth(_ auth: inout RequestAuth, scope: String, secrets: inout [String: String]) {
        secrets[scope + ".token"] = auth.token; secrets[scope + ".username"] = auth.username; secrets[scope + ".password"] = auth.password
        auth.token = ""; auth.username = ""; auth.password = ""; stripAdvancedAuth(&auth, scope: scope, secrets: &secrets)
    }
    private static func restoreAllAuth(_ auth: inout RequestAuth, scope: String, secrets: [String: String]) {
        auth.token = secrets[scope + ".token"] ?? auth.token; auth.username = secrets[scope + ".username"] ?? auth.username; auth.password = secrets[scope + ".password"] ?? auth.password
        restoreAdvancedAuth(&auth, scope: scope, secrets: secrets)
    }

}

/// Entity-level last-edit-wins merge. Deletions are retained as tombstones; unrelated edits survive.
public struct WorkspaceSyncState: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var key: String
        public var payload: Data?
        public var changed: Date
        public var device: UUID
    }
    public var device = UUID()
    public var records: [Record] = []
    public init() {}
    private struct Collection: Codable { var id: UUID; var name: String; var requests: [UUID]; var position: Int; var folders: [RequestFolder]?; var defaults: RequestDefaults? }
    private struct Request: Codable { var collection: UUID; var request: APIRequest; var position: Int }
    private struct Environment: Codable { var environment: APIEnvironment; var position: Int }

    public mutating func capture(_ workspace: Workspace, now: Date = Date(), includeCredentials: Bool = false) throws {
        var ignored: [String: String] = [:]
        let workspace = SecretPolicy.strip(workspace, secrets: &ignored, files: true, credentials: !includeCredentials)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var current: [String: Data] = [:]
        for (index, collection) in workspace.collections.enumerated() {
            current["collection.\(collection.id)"] = try encoder.encode(Collection(id: collection.id, name: collection.name, requests: collection.requests.map(\.id), position: index, folders: collection.folders, defaults: collection.defaults))
            for (position, request) in collection.requests.enumerated() { current["request.\(request.id)"] = try encoder.encode(Request(collection: collection.id, request: request, position: position)) }
        }
        for (position, environment) in workspace.environments.enumerated() { current["environment.\(environment.id)"] = try encoder.encode(Environment(environment: environment, position: position)) }
        if let globals = workspace.globals { current["globals"] = try encoder.encode(globals) }
        let previous = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for key in Set(current.keys).union(previous.keys) where current[key] != previous[key]?.payload {
            let date = max(now, (previous[key]?.changed ?? .distantPast).addingTimeInterval(0.001))
            let record = Record(key: key, payload: current[key], changed: date, device: device)
            records.removeAll { $0.key == key }; records.append(record)
        }
        records.sort { $0.key < $1.key }
    }
    public mutating func merge(_ other: WorkspaceSyncState) {
        for incoming in other.records {
            if let i = records.firstIndex(where: { $0.key == incoming.key }) {
                let local = records[i]
                if incoming.changed > local.changed || (incoming.changed == local.changed && incoming.device.uuidString > local.device.uuidString) { records[i] = incoming }
            } else { records.append(incoming) }
        }
        records.sort { $0.key < $1.key }
    }
    public func workspace(local: Workspace, includeCredentials: Bool = false) throws -> Workspace {
        let decoder = JSONDecoder()
        var collections: [Collection] = [], requests: [Request] = [], environments: [Environment] = []
        var globals: [Field]?
        for record in records {
            guard let data = record.payload else { continue }
            if record.key.hasPrefix("collection.") { collections.append(try decoder.decode(Collection.self, from: data)) }
            if record.key.hasPrefix("request.") { requests.append(try decoder.decode(Request.self, from: data)) }
            if record.key.hasPrefix("environment.") { environments.append(try decoder.decode(Environment.self, from: data)) }
            if record.key == "globals" { globals = try decoder.decode([Field].self, from: data) }
        }
        collections.sort { $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position }
        environments.sort { $0.position == $1.position ? $0.environment.id.uuidString < $1.environment.id.uuidString : $0.position < $1.position }
        var result = local
        result.collections = collections.map { item in
            var collection = RequestCollection(name: item.name)
            collection.id = item.id; collection.folders = item.folders; collection.defaults = item.defaults
            collection.requests = requests.filter { $0.collection == item.id }.sorted { $0.position == $1.position ? $0.request.id.uuidString < $1.request.id.uuidString : $0.position < $1.position }.map(\.request)
            return collection
        }
        result.environments = environments.map(\.environment)
        result.globals = records.contains { $0.key == "globals" } ? globals : local.globals
        if !result.environments.contains(where: { $0.id == result.selectedEnvironmentID }) { result.selectedEnvironmentID = result.environments.first?.id }
        var secrets: [String: String] = [:]
        _ = SecretPolicy.strip(local, secrets: &secrets, files: false, credentials: !includeCredentials)
        return SecretPolicy.restore(result, secrets: secrets, local: local, credentials: !includeCredentials)
    }
}

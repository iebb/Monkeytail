import Foundation

public enum SecretPolicy {
    public static func isSensitive(_ name: String) -> Bool {
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: "_")
        return ["authorization", "cookie", "set_cookie", "proxy_authorization"].contains(normalized)
            || ["token", "secret", "password", "api_key", "apikey", "credential"].contains { normalized.contains($0) }
    }
    /// Removes credential values, leaving stable keys so each device can restore its own secrets.
    public static func strip(_ source: Workspace, secrets: inout [String: String], files: Bool) -> Workspace {
        var copy = source
        func clean(_ fields: [Field], scope: String) -> [Field] {
            fields.map { field in
                var field = field
                if field.isSecret { secrets["\(scope).field.\(field.id)"] = field.value; field.value = ""; field.secret = true }
                return field
            }
        }
        for c in copy.collections.indices {
            for r in copy.collections[c].requests.indices {
                var request = copy.collections[c].requests[r]
                request.headers = clean(request.headers, scope: "request.\(request.id).headers"); request.query = clean(request.query, scope: "request.\(request.id).query"); request.form = clean(request.form, scope: "request.\(request.id).form")
                if var url = URLComponents(string: request.url) {
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
                secrets["auth.\(request.id).token"] = request.auth.token
                secrets["auth.\(request.id).password"] = request.auth.password
                secrets["auth.\(request.id).username"] = request.auth.username
                request.auth.token = ""; request.auth.password = ""; request.auth.username = ""
                if request.multipart != nil {
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
                            if SecretPolicy.isSensitive(request.multipart![index].name) { request.multipart![index].value = "" }
                        }
                    }
                    // Enabling scripts is a per-device decision, even for synced scripts.
                    request.scriptsEnabled = false
                }
                copy.collections[c].requests[r] = request
            }
        }
        for e in copy.environments.indices { copy.environments[e].variables = clean(copy.environments[e].variables, scope: "environment.\(copy.environments[e].id)") }
        secrets["proxy.password"] = copy.proxy.password; secrets["proxy.username"] = copy.proxy.username; copy.proxy.password = ""; copy.proxy.username = ""
        return copy
    }
    public static func restore(_ source: Workspace, secrets: [String: String], local: Workspace? = nil) -> Workspace {
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
                                if SecretPolicy.isSensitive(part.name) { request.multipart![i].value = part.value }
                            }
                        }
                    }
                    request.scriptsEnabled = previous.scriptsEnabled
                }
                copy.collections[c].requests[r] = request
            }
        }
        for e in copy.environments.indices { copy.environments[e].variables = restoreFields(copy.environments[e].variables, scope: "environment.\(copy.environments[e].id)") }
        copy.proxy.password = secrets["proxy.password"] ?? copy.proxy.password
        copy.proxy.username = secrets["proxy.username"] ?? copy.proxy.username
        return copy
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
    private struct Collection: Codable { var id: UUID; var name: String; var requests: [UUID]; var position: Int }
    private struct Request: Codable { var collection: UUID; var request: APIRequest; var position: Int }
    private struct Environment: Codable { var environment: APIEnvironment; var position: Int }

    public mutating func capture(_ workspace: Workspace, now: Date = Date()) throws {
        var ignored: [String: String] = [:]
        let workspace = SecretPolicy.strip(workspace, secrets: &ignored, files: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var current: [String: Data] = [:]
        for (index, collection) in workspace.collections.enumerated() {
            current["collection.\(collection.id)"] = try encoder.encode(Collection(id: collection.id, name: collection.name, requests: collection.requests.map(\.id), position: index))
            for (position, request) in collection.requests.enumerated() { current["request.\(request.id)"] = try encoder.encode(Request(collection: collection.id, request: request, position: position)) }
        }
        for (position, environment) in workspace.environments.enumerated() { current["environment.\(environment.id)"] = try encoder.encode(Environment(environment: environment, position: position)) }
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
    public func workspace(local: Workspace) throws -> Workspace {
        let decoder = JSONDecoder()
        var collections: [Collection] = [], requests: [Request] = [], environments: [Environment] = []
        for record in records {
            guard let data = record.payload else { continue }
            if record.key.hasPrefix("collection.") { collections.append(try decoder.decode(Collection.self, from: data)) }
            if record.key.hasPrefix("request.") { requests.append(try decoder.decode(Request.self, from: data)) }
            if record.key.hasPrefix("environment.") { environments.append(try decoder.decode(Environment.self, from: data)) }
        }
        collections.sort { $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position }
        environments.sort { $0.position == $1.position ? $0.environment.id.uuidString < $1.environment.id.uuidString : $0.position < $1.position }
        var result = local
        result.collections = collections.map { item in
            var collection = RequestCollection(name: item.name)
            collection.id = item.id
            collection.requests = requests.filter { $0.collection == item.id }.sorted { $0.position == $1.position ? $0.request.id.uuidString < $1.request.id.uuidString : $0.position < $1.position }.map(\.request)
            return collection
        }
        result.environments = environments.map(\.environment)
        if !result.environments.contains(where: { $0.id == result.selectedEnvironmentID }) { result.selectedEnvironmentID = result.environments.first?.id }
        var secrets: [String: String] = [:]
        _ = SecretPolicy.strip(local, secrets: &secrets, files: false)
        return SecretPolicy.restore(result, secrets: secrets, local: local)
    }
}

import Foundation

/// Insomnia v4 exports (JSON or YAML) and v5 collection, environment and spec YAML files.
enum InsomniaImport {
    static func decode(_ root: [String: Any], resources: [[String: Any]]) throws -> CollectionImport {
        var warnings: [String] = [], collections: [RequestCollection] = [], environments: [APIEnvironment] = []
        let kinds: Set = ["request", "request_group", "websocket_request", "grpc_request"]
        let items = resources.filter { kinds.contains($0["_type"] as? String ?? "") }
        let children = Dictionary(grouping: items) { $0["parentId"] as? String ?? "" }
        func tree(_ parent: String, depth: Int) throws -> [[String: Any]] {
            guard depth < 32 else { throw ClientError("Insomnia folders are nested too deeply.") }
            return try (children[parent] ?? []).sorted { number($0["metaSortKey"]) < number($1["metaSortKey"]) }.map { item in
                var item = item
                if item["_type"] as? String == "request_group" { item["children"] = try tree(CollectionCodec.string(item["_id"]), depth: depth + 1) }
                return item
            }
        }
        let workspaces = resources.filter { $0["_type"] as? String == "workspace" }
        let workspaceIDs = Set(workspaces.map { CollectionCodec.string($0["_id"]) })
        // Monkeytail's own v4 export stores each collection as a top-level folder.
        let legacy = (root["__export_source"] as? String ?? "").hasPrefix("monkeytail")
        var baseVariables: [String: [Field]] = [:]
        let baseIDs = Set(resources.filter { $0["_type"] as? String == "environment" && workspaceIDs.contains($0["parentId"] as? String ?? "") }.map { CollectionCodec.string($0["_id"]) })
        for resource in resources where resource["_type"] as? String == "environment" {
            let parent = resource["parentId"] as? String ?? "", variables = self.variables(resource["data"])
            if !legacy && workspaceIDs.contains(parent) { baseVariables[parent, default: []] += variables; continue }
            if !legacy && baseIDs.contains(CollectionCodec.string(resource["_id"])) { continue }
            environments.append(APIEnvironment(name: resource["name"] as? String ?? "Environment", variables: variables))
        }
        for workspace in workspaces {
            let id = CollectionCodec.string(workspace["_id"]), top = try tree(id, depth: 0)
            if legacy {
                for group in top where group["children"] != nil {
                    collections.append(try collection(name: group["name"] as? String ?? "Insomnia collection", items: group["children"] as? [[String: Any]] ?? [], defaults: group, warnings: &warnings))
                }
                let loose = top.filter { $0["children"] == nil }
                if !loose.isEmpty { collections.append(try collection(name: workspace["name"] as? String ?? "Insomnia collection", items: loose, defaults: nil, warnings: &warnings)) }
            } else {
                var collection = try collection(name: workspace["name"] as? String ?? "Insomnia collection", items: top, defaults: nil, warnings: &warnings)
                if let variables = baseVariables[id], !variables.isEmpty { collection.defaults = collection.defaults ?? RequestDefaults(); collection.defaults?.variables = variables }
                if let text = CollectionCodec.description(workspace["description"]) { collection.defaults = collection.defaults ?? RequestDefaults(); collection.defaults?.description = text }
                collections.append(collection)
            }
        }
        let known = workspaceIDs.union(items.compactMap { $0["_type"] as? String == "request_group" ? $0["_id"] as? String : nil })
        let orphans = try children.keys.filter { !known.contains($0) }.sorted().flatMap { try tree($0, depth: 0) }
        if !orphans.isEmpty { collections.append(try collection(name: "Insomnia collection", items: orphans, defaults: nil, warnings: &warnings)) }
        return finish(Workspace(collections: collections, environments: environments), warnings: warnings)
    }

    static func decodeV5(_ root: [String: Any]) throws -> CollectionImport {
        var warnings: [String] = []
        let type = root["type"] as? String ?? "", name = root["name"] as? String ?? "Insomnia collection"
        let environment = root["environments"] as? [String: Any]
        let base = variables(environment?["data"])
        let environments = (environment?["subEnvironments"] as? [[String: Any]] ?? []).map { APIEnvironment(name: $0["name"] as? String ?? "Environment", variables: variables($0["data"])) }
        if type.hasPrefix("environment.") {
            var workspace = Workspace(environments: environments); workspace.globals = base.isEmpty ? nil : base
            return CollectionImport(workspace: workspace)
        }
        if type.hasPrefix("mock.") { throw ClientError("Insomnia mock server files contain routes, not requests. Export the collection instead.") }
        let items = root["collection"] as? [[String: Any]] ?? []
        if items.isEmpty, let contents = (root["spec"] as? [String: Any])?["contents"] as? [String: Any], contents["openapi"] != nil || contents["swagger"] != nil {
            return try OpenAPICodec.decode(CollectionCodec.json(contents))
        }
        var collection = try collection(name: name, items: items, defaults: nil, warnings: &warnings)
        if !base.isEmpty { collection.defaults = collection.defaults ?? RequestDefaults(); collection.defaults?.variables = base }
        if let text = CollectionCodec.description((root["meta"] as? [String: Any])?["description"]) { collection.defaults = collection.defaults ?? RequestDefaults(); collection.defaults?.description = text }
        return finish(Workspace(collections: [collection], environments: environments), warnings: warnings)
    }

    private static func finish(_ workspace: Workspace, warnings: [String]) -> CollectionImport {
        var warnings = warnings
        let requests = workspace.collections.flatMap(\.requests)
        if requests.contains(where: { !$0.preScript.isEmpty || !$0.postScript.isEmpty }) || workspace.collections.flatMap({ $0.folders ?? [] }).contains(where: { !$0.defaults.preScript.isEmpty || !$0.defaults.postScript.isEmpty }) {
            warnings.append("Imported scripts run when you send. The insomnia object is available as an alias of pm.")
        }
        if requests.contains(where: { ($0.url + $0.body + $0.headers.map(\.value).joined()).contains("{%") }) { warnings.append("Insomnia template tags such as {% response %} are not evaluated. Replace them with variables or scripts.") }
        return CollectionImport(workspace: workspace, warnings: InterchangeImport.unique(warnings))
    }

    private static func collection(name: String, items: [[String: Any]], defaults source: [String: Any]?, warnings: inout [String]) throws -> RequestCollection {
        var collection = RequestCollection(name: name), folders: [RequestFolder] = [], skipped = 0
        func walk(_ items: [[String: Any]], parent: UUID?, depth: Int) throws {
            guard depth < 32, folders.count < 2000 else { throw ClientError("Insomnia folders exceed the depth or count limit.") }
            for item in items {
                let id = CollectionCodec.string(item["_id"] ?? (item["meta"] as? [String: Any])?["id"]), type = item["_type"] as? String
                if item["children"] != nil || type == "request_group" {
                    var folder = RequestFolder(name: item["name"] as? String ?? "Folder", parentID: parent)
                    folder.defaults = defaults(item, inherit: true, warnings: &warnings)
                    folders.append(folder)
                    try walk(item["children"] as? [[String: Any]] ?? [], parent: folder.id, depth: depth + 1)
                } else if id.hasPrefix("ws-req") || type == "websocket_request" {
                    var request = APIRequest(name: item["name"] as? String ?? "WebSocket", url: CollectionCodec.normalizeInsomnia(CollectionCodec.string(item["url"])))
                    request.transport = .websocket; request.folderID = parent
                    request.headers = CollectionCodec.fields(item["headers"] as? [[String: Any]] ?? []); request.query = CollectionCodec.fields(item["parameters"] as? [[String: Any]] ?? [])
                    request.auth = auth(item, warnings: &warnings)
                    collection.requests.append(request)
                } else if type == "request" || id.hasPrefix("req_") || (type == nil && item["method"] != nil) {
                    var request = try self.request(item, warnings: &warnings); request.folderID = parent
                    collection.requests.append(request)
                } else { skipped += 1 }
            }
        }
        try walk(items, parent: nil, depth: 0)
        if skipped > 0 { warnings.append("Skipped \(skipped) gRPC, Socket.IO or MCP \(skipped == 1 ? "request" : "requests"). Monkeytail imports HTTP, GraphQL and WebSocket requests.") }
        collection.folders = folders.isEmpty ? nil : folders
        if let source { collection.defaults = defaults(source, inherit: false, warnings: &warnings) }
        return collection
    }

    private static func request(_ item: [String: Any], warnings: inout [String]) throws -> APIRequest {
        let normalize = CollectionCodec.normalizeInsomnia
        var request = APIRequest(name: item["name"] as? String ?? "Untitled", method: (item["method"] as? String ?? "GET").uppercased(), url: normalize(CollectionCodec.string(item["url"])))
        request.description = CollectionCodec.description(item["description"]) ?? CollectionCodec.description((item["meta"] as? [String: Any])?["description"])
        request.impersonation = try CollectionCodec.decodeTransport(item["_monkeytail"])
        request.headers = CollectionCodec.fields(item["headers"] as? [[String: Any]] ?? [])
        request.query = CollectionCodec.fields(item["parameters"] as? [[String: Any]] ?? [])
        if let path = item["pathParameters"] as? [[String: Any]], !path.isEmpty { request.pathVariables = CollectionCodec.fields(path) }
        request.auth = auth(item, warnings: &warnings)
        let settings = item["settings"] as? [String: Any]
        request.followRedirects = (item["settingFollowRedirects"] ?? settings?["followRedirects"]) as? String != "off"
        if let body = item["body"] as? [String: Any], let mime = body["mimeType"] as? String, !mime.isEmpty {
            if mime == "application/x-www-form-urlencoded" { request.bodyKind = .form; request.form = CollectionCodec.fields(body["params"] as? [[String: Any]] ?? []) }
            else if mime.contains("multipart") {
                request.bodyKind = .multipart
                request.multipart = (body["params"] as? [[String: Any]] ?? []).map { field in
                    MultipartPart(name: normalize(CollectionCodec.string(field["name"])), value: normalize(CollectionCodec.string(field["value"])), enabled: !(field["disabled"] as? Bool ?? false),
                                  file: field["type"] as? String == "file" ? RequestFile(filename: CollectionCodec.string(field["fileName"]), mimeType: field["contentType"] as? String ?? "application/octet-stream") : nil)
                }
                if request.multipart?.contains(where: { $0.file != nil }) == true { warnings.append("Choose imported attachment files on this device before sending.") }
            } else if mime == "application/graphql" {
                let text = normalize(body["text"] as? String ?? "")
                let payload = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
                var graphql = GraphQLRequest(); graphql.query = payload["query"] as? String ?? ""
                if let variables = payload["variables"], !(variables is NSNull), let data = try? JSONSerialization.data(withJSONObject: variables, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) { graphql.variables = String(decoding: data, as: UTF8.self) }
                graphql.operationName = payload["operationName"] as? String ?? ""
                request.transport = .graphql; request.graphql = graphql; request.bodyKind = .json; request.body = text
                if !request.headers.contains(where: { $0.name.lowercased() == "content-type" }) { request.headers.append(Field("Content-Type", "application/json")) }
            } else if body["fileName"] != nil {
                request.bodyKind = .file; request.fileBody = RequestFile(filename: CollectionCodec.string(body["fileName"]), mimeType: mime)
                warnings.append("Choose the imported body file on this device before sending.")
            } else {
                request.bodyKind = mime.contains("json") ? .json : .text; request.body = normalize(body["text"] as? String ?? "")
                if !request.headers.contains(where: { $0.name.lowercased() == "content-type" }) { request.headers.append(Field("Content-Type", mime)) }
            }
        }
        let scripts = item["scripts"] as? [String: Any]
        request.preScript = (item["preRequestScript"] ?? scripts?["preRequest"]) as? String ?? ""
        request.postScript = (item["afterResponseScript"] ?? scripts?["afterResponse"]) as? String ?? ""
        CollectionCodec.decodeAdvanced(item["_monkeytail"], into: &request)
        return request
    }

    /// Requests without authentication inherit it from their folder, as in Insomnia.
    private static func auth(_ item: [String: Any], warnings: inout [String]) -> RequestAuth {
        guard let source = item["authentication"] as? [String: Any], source["type"] != nil else { var auth = RequestAuth(); auth.kind = .inherit; return auth }
        return CollectionCodec.decodeAuth(source.mapValues { ($0 as? String).map(CollectionCodec.normalizeInsomnia) ?? $0 }, postman: false, warnings: &warnings)
    }

    private static func defaults(_ item: [String: Any], inherit: Bool, warnings: inout [String]) -> RequestDefaults {
        var defaults = RequestDefaults()
        defaults.headers = CollectionCodec.fields(item["headers"] as? [[String: Any]] ?? [])
        defaults.variables = variables(item["environment"])
        defaults.auth = auth(item, warnings: &warnings)
        if defaults.auth.kind == .inherit && !inherit { defaults.auth.kind = .none }
        let scripts = item["scripts"] as? [String: Any]
        defaults.preScript = (item["preRequestScript"] ?? scripts?["preRequest"]) as? String ?? ""
        defaults.postScript = (item["afterResponseScript"] ?? scripts?["afterResponse"]) as? String ?? ""
        defaults.description = CollectionCodec.description(item["description"]) ?? CollectionCodec.description((item["meta"] as? [String: Any])?["description"])
        return defaults
    }

    /// Flattens nested environment objects into dotted names, matching `{{ _.parent.child }}`.
    static func variables(_ data: Any?) -> [Field] {
        var result: [Field] = []
        func add(_ value: Any, path: String, depth: Int) {
            if let object = value as? [String: Any], depth < 8, !object.isEmpty { for key in object.keys.sorted() { add(object[key]!, path: path.isEmpty ? key : path + "." + key, depth: depth + 1) } }
            else { result.append(Field(path, CollectionCodec.normalizeInsomnia(CollectionCodec.string(value)))) }
        }
        if let data = data as? [String: Any] { for key in data.keys.sorted() { add(data[key]!, path: key, depth: 0) } }
        return result
    }

    private static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(CollectionCodec.string(value)) ?? 0 }
}

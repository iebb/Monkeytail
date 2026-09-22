import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable { case native = "Monkeytail", postman = "Postman v2.1", insomnia = "Insomnia v4"; public var id: String { rawValue } }
public struct CollectionImport {
    public var workspace: Workspace
    public var warnings: [String]
    public var includesSettings: Bool
    public init(workspace: Workspace, warnings: [String] = [], includesSettings: Bool = false) { self.workspace = workspace; self.warnings = warnings; self.includesSettings = includesSettings }
}

public enum CollectionCodec {
    public static func decode(_ data: Data) throws -> CollectionImport {
        guard data.count <= 10 * 1024 * 1024 else { throw ClientError("Import files must be smaller than 10 MB.") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError("Choose a JSON collection or environment file.") }
        if root["collections"] != nil && root["version"] != nil {
            let workspace = try JSONDecoder().decode(Workspace.self, from: data)
            guard workspace.version == 1 else { throw ClientError("This Monkeytail file uses an unsupported version.") }
            return CollectionImport(workspace: workspace, includesSettings: true)
        }
        if root["info"] != nil && root["item"] != nil { return try postman(root) }
        if let values = root["values"] as? [[String: Any]] {
            return CollectionImport(workspace: Workspace(environments: [APIEnvironment(name: root["name"] as? String ?? "Imported environment", variables: fields(values))]))
        }
        if let resources = root["resources"] as? [[String: Any]] { return try insomnia(root, resources: resources) }
        throw ClientError("Unsupported format. Import Monkeytail JSON, Postman v2/v2.1 collections or environments, or Insomnia v4 JSON. Export YAML as JSON in the source app first.")
    }

    public static func encode(_ workspace: Workspace, format: ExportFormat) throws -> Data {
        switch format {
        case .native:
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(workspace)
        case .postman:
            let environment = workspace.environments.first { $0.id == workspace.selectedEnvironmentID }
            let root: [String: Any] = [
                "info": ["name": "Monkeytail workspace", "_postman_id": UUID().uuidString, "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"],
                "variable": (environment?.variables ?? []).map { ["key": $0.name, "value": $0.value, "disabled": !$0.enabled] as [String: Any] },
                "item": workspace.collections.map { collection in ["name": collection.name, "item": collection.requests.map(postmanItem)] as [String: Any] }
            ]
            return try json(root)
        case .insomnia:
            let workspaceID = "wrk_" + UUID().uuidString
            var resources: [[String: Any]] = [["_id": workspaceID, "_type": "workspace", "name": "Monkeytail workspace", "scope": "collection", "description": "Exported from Monkeytail"]]
            for environment in workspace.environments {
                resources.append(["_id": "env_" + environment.id.uuidString, "_type": "environment", "parentId": workspaceID, "name": environment.name, "data": environment.values])
            }
            for collection in workspace.collections {
                let groupID = "fld_" + collection.id.uuidString
                resources.append(["_id": groupID, "_type": "request_group", "parentId": workspaceID, "name": collection.name])
                for request in collection.requests {
                    var body: [String: Any] = [:]
                    switch request.bodyKind {
                    case .none: break
                    case .json, .text: body = ["mimeType": request.bodyKind == .json ? "application/json" : "text/plain", "text": request.body]
                    case .form: body = ["mimeType": "application/x-www-form-urlencoded", "params": request.form.map(insomniaField)]
                    }
                    var auth: [String: Any] = [:]
                    if request.auth.kind == .bearer { auth = ["type": "bearer", "token": request.auth.token] }
                    if request.auth.kind == .basic { auth = ["type": "basic", "username": request.auth.username, "password": request.auth.password] }
                    resources.append(["_id": "req_" + request.id.uuidString, "_type": "request", "parentId": groupID, "name": request.name, "url": request.url, "method": request.method,
                                      "headers": request.headers.map(insomniaField), "parameters": request.query.map(insomniaField), "body": body, "authentication": auth,
                                      "settingFollowRedirects": request.followRedirects ? "on" : "off", "preRequestScript": request.preScript, "afterResponseScript": request.postScript])
                }
            }
            return try json(["_type": "export", "__export_format": 4, "__export_date": ISO8601DateFormatter().string(from: Date()), "__export_source": "monkeytail:1.0", "resources": resources])
        }
    }

    private static func postman(_ root: [String: Any]) throws -> CollectionImport {
        var requests: [APIRequest] = [], warnings: [String] = []
        func walk(_ items: [[String: Any]], path: String, inheritedAuth: [String: Any]?, inheritedEvents: [[String: Any]]) throws {
            for item in items {
                let name = item["name"] as? String ?? "Untitled"
                let auth = item["auth"] as? [String: Any] ?? inheritedAuth
                let events = inheritedEvents + (item["event"] as? [[String: Any]] ?? [])
                if let children = item["item"] as? [[String: Any]] {
                    try walk(children, path: path + name + " / ", inheritedAuth: auth, inheritedEvents: events)
                    continue
                }
                let source = item["request"] as? [String: Any] ?? ["url": item["request"] as? String ?? ""]
                let urlObject = source["url"] as? [String: Any]
                let raw = source["url"] as? String ?? urlObject?["raw"] as? String ?? ""
                guard !raw.isEmpty else { throw ClientError("Request ‘\(name)’ is missing a raw URL.") }
                var request = APIRequest(name: path + name, method: source["method"] as? String ?? "GET", url: raw)
                request.headers = fields(source["header"] as? [[String: Any]] ?? [])
                if let query = urlObject?["query"] as? [[String: Any]] {
                    request.query = fields(query)
                    request.url = withoutQuery(raw)
                }
                request.auth = decodeAuth(source["auth"] as? [String: Any] ?? auth, postman: true, warnings: &warnings)
                if let body = source["body"] as? [String: Any] {
                    switch body["mode"] as? String {
                    case "raw":
                        request.body = body["raw"] as? String ?? ""
                        let options = body["options"] as? [String: Any]
                        let language = (options?["raw"] as? [String: Any])?["language"] as? String
                        request.bodyKind = language == "json" || request.headers.contains { $0.name.lowercased() == "content-type" && $0.value.contains("json") } ? .json : .text
                    case "urlencoded": request.bodyKind = .form; request.form = fields(body["urlencoded"] as? [[String: Any]] ?? [])
                    case "graphql":
                        request.bodyKind = .json
                        let graph = body["graphql"] as? [String: Any] ?? [:]
                        var payload: [String: Any] = ["query": graph["query"] as? String ?? ""]
                        if let variables = graph["variables"] as? String, !variables.isEmpty { payload["variables"] = try JSONTools.parse(variables) }
                        request.body = String(decoding: try json(payload), as: UTF8.self)
                    case nil: break
                    default: throw ClientError("‘\(name)’ uses an unsupported body mode. Convert multipart or file bodies to raw text before importing.")
                    }
                }
                for event in events {
                    let script = event["script"] as? [String: Any]
                    let code = (script?["exec"] as? [String])?.joined(separator: "\n") ?? script?["exec"] as? String ?? ""
                    if event["listen"] as? String == "prerequest" { request.preScript += code + "\n" }
                    if event["listen"] as? String == "test" { request.postScript += code + "\n" }
                }
                requests.append(request)
            }
        }
        try walk(root["item"] as? [[String: Any]] ?? [], path: "", inheritedAuth: root["auth"] as? [String: Any], inheritedEvents: root["event"] as? [[String: Any]] ?? [])
        let name = (root["info"] as? [String: Any])?["name"] as? String ?? "Postman collection"
        let variables = fields(root["variable"] as? [[String: Any]] ?? [])
        if requests.contains(where: { !$0.preScript.isEmpty || !$0.postScript.isEmpty }) { warnings.append("Scripts were imported disabled. Review them before enabling; only the documented scripting API and basic pm aliases are supported.") }
        return CollectionImport(workspace: Workspace(collections: [RequestCollection(name: name, requests: requests)], environments: variables.isEmpty ? [] : [APIEnvironment(name: name, variables: variables)]), warnings: warnings)
    }

    private static func insomnia(_ root: [String: Any], resources: [[String: Any]]) throws -> CollectionImport {
        var warnings: [String] = [], collections: [RequestCollection] = [], environments: [APIEnvironment] = []
        let groups = resources.filter { ["workspace", "request_group"].contains($0["_type"] as? String ?? "") }
        for resource in resources where resource["_type"] as? String == "environment" {
            let data = resource["data"] as? [String: Any] ?? [:]
            environments.append(APIEnvironment(name: resource["name"] as? String ?? "Environment", variables: data.keys.sorted().map { Field($0, string(data[$0])) }))
        }
        for resource in resources where resource["_type"] as? String == "request" {
            let parent = resource["parentId"] as? String ?? ""
            let groupName = groups.first { $0["_id"] as? String == parent }?["name"] as? String ?? "Insomnia collection"
            if !collections.contains(where: { $0.name == groupName }) { collections.append(RequestCollection(name: groupName)) }
            var request = APIRequest(name: resource["name"] as? String ?? "Untitled", method: resource["method"] as? String ?? "GET", url: normalizeInsomnia(resource["url"] as? String ?? ""))
            request.headers = fields(resource["headers"] as? [[String: Any]] ?? [])
            request.query = fields(resource["parameters"] as? [[String: Any]] ?? [])
            request.auth = decodeAuth(resource["authentication"] as? [String: Any], postman: false, warnings: &warnings)
            request.followRedirects = resource["settingFollowRedirects"] as? String != "off"
            if let body = resource["body"] as? [String: Any], let mime = body["mimeType"] as? String, !mime.isEmpty {
                if mime == "application/x-www-form-urlencoded" { request.bodyKind = .form; request.form = fields(body["params"] as? [[String: Any]] ?? []) }
                else if mime.contains("multipart") || body["fileName"] != nil { throw ClientError("‘\(request.name)’ uses multipart or file content. Convert its body to raw text before importing.") }
                else {
                    request.bodyKind = mime.contains("json") ? .json : .text; request.body = normalizeInsomnia(body["text"] as? String ?? "")
                    if !request.headers.contains(where: { $0.name.lowercased() == "content-type" }) { request.headers.append(Field("Content-Type", mime)) }
                }
            }
            request.preScript = resource["preRequestScript"] as? String ?? ""
            request.postScript = resource["afterResponseScript"] as? String ?? ""
            collections[collections.firstIndex { $0.name == groupName }!].requests.append(request)
        }
        if collections.flatMap(\.requests).contains(where: { !$0.preScript.isEmpty || !$0.postScript.isEmpty }) { warnings.append("Imported scripts are disabled until reviewed. Insomnia-specific scripting APIs may require adaptation.") }
        return CollectionImport(workspace: Workspace(collections: collections, environments: environments), warnings: warnings)
    }

    private static func decodeAuth(_ source: [String: Any]?, postman: Bool, warnings: inout [String]) -> RequestAuth {
        var auth = RequestAuth()
        guard let source, let type = source["type"] as? String else { return auth }
        var values = source
        if postman { values = (source[type] as? [[String: Any]] ?? []).reduce(into: [:]) { $0[$1["key"] as? String ?? ""] = $1["value"] } }
        switch type {
        case "bearer": auth.kind = .bearer; auth.token = string(values["token"])
        case "basic": auth.kind = .basic; auth.username = string(values["username"]); auth.password = string(values["password"])
        case "noauth", "none", "": break
        default: warnings.append("Authentication type ‘\(type)’ is unsupported. Configure an Authorization header manually.")
        }
        return auth
    }
    private static func postmanItem(_ request: APIRequest) -> [String: Any] {
        var source: [String: Any] = ["method": request.method, "header": request.headers.map(postmanField)]
        var query = request.query
        if let components = URLComponents(string: request.url) {
            query.insert(contentsOf: (components.queryItems ?? []).map { Field($0.name, $0.value ?? "") }, at: 0)
        }
        var raw = withoutQuery(request.url)
        if !query.isEmpty { raw += "?" + query.filter(\.enabled).map { RequestBuilder.formEncode($0.name) + "=" + RequestBuilder.formEncode($0.value) }.joined(separator: "&") }
        source["url"] = ["raw": raw, "query": query.map(postmanField)]
        switch request.bodyKind {
        case .none: break
        case .json, .text: source["body"] = ["mode": "raw", "raw": request.body, "options": ["raw": ["language": request.bodyKind == .json ? "json" : "text"]]]
        case .form: source["body"] = ["mode": "urlencoded", "urlencoded": request.form.map(postmanField)]
        }
        switch request.auth.kind {
        case .none: source["auth"] = ["type": "noauth"]
        case .bearer: source["auth"] = ["type": "bearer", "bearer": [["key": "token", "value": request.auth.token, "type": "string"]]]
        case .basic: source["auth"] = ["type": "basic", "basic": [["key": "username", "value": request.auth.username, "type": "string"], ["key": "password", "value": request.auth.password, "type": "string"]]]
        }
        var item: [String: Any] = ["name": request.name, "request": source]
        item["event"] = [("prerequest", request.preScript), ("test", request.postScript)].filter { !$0.1.isEmpty }.map { ["listen": $0.0, "script": ["type": "text/javascript", "exec": $0.1.components(separatedBy: "\n")]] as [String: Any] }
        return item
    }
    private static func fields(_ source: [[String: Any]]) -> [Field] {
        source.map { Field(normalizeInsomnia($0["key"] as? String ?? $0["name"] as? String ?? ""), normalizeInsomnia(string($0["value"])), enabled: !($0["disabled"] as? Bool ?? false) && ($0["enabled"] as? Bool ?? true)) }
    }
    private static func string(_ value: Any?) -> String {
        guard let value else { return "" }
        if let value = value as? String { return value }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) { return String(decoding: data, as: UTF8.self) }
        return String(describing: value)
    }
    private static func normalizeInsomnia(_ value: String) -> String {
        value.replacingOccurrences(of: #"\{\{\s*_\.([\w.\-]+)\s*\}\}"#, with: "{{$1}}", options: .regularExpression)
    }
    private static func withoutQuery(_ value: String) -> String {
        let withoutFragment = String(value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        return String(withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }
    private static func postmanField(_ field: Field) -> [String: Any] { ["key": field.name, "value": field.value, "disabled": !field.enabled, "type": "text"] }
    private static func insomniaField(_ field: Field) -> [String: Any] { ["name": field.name, "value": field.value, "disabled": !field.enabled] }
    private static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
}

import Foundation

public struct ImportFile: Sendable {
    /// Path relative to the chosen folder, or a filename.
    public var path: String
    public var text: String
    public init(path: String, text: String) { self.path = path; self.text = text }
}

/// Detects and decodes collections exported by other API clients. No account or network access is involved.
public enum InterchangeImport {
    static let unsupportedMessage = "Unsupported format. Import cURL, Postman (v1, v2, v2.1, environments, globals or data dumps), Insomnia (v4 JSON/YAML or v5 YAML), Bruno (.bru files, folders or JSON), Hoppscotch, Thunder Client, HAR, .http files, OpenAPI/Swagger, or Monkeytail JSON."

    /// Decodes any supported text other than cURL.
    public static func decode(_ text: String, filename: String? = nil) throws -> CollectionImport {
        guard text.utf8.count <= 40 * 1024 * 1024 else { throw ClientError("Imports must be smaller than 40 MB.") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError("Paste or choose something to import.") }
        let data = Data(trimmed.utf8), lowered = (filename ?? "").lowercased()
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            let object: Any
            do { object = try JSONSerialization.jsonObject(with: data) } catch { throw ClientError("The JSON could not be read. Check that the file is complete.") }
            if let root = object as? [String: Any], root["openapi"] != nil || root["swagger"] != nil { return try OpenAPICodec.decode(data) }
            return try CollectionCodec.decode(data)
        }
        if lowered.hasSuffix(".bru") || BrunoImport.looksLikeBru(trimmed) { return try BrunoImport.decode(files: [ImportFile(path: filename ?? "request.bru", text: trimmed)], name: "Bruno collection") }
        if lowered.hasSuffix(".http") || lowered.hasSuffix(".rest") || HTTPFileImport.looksLikeHTTPFile(trimmed) {
            return try HTTPFileImport.decode(trimmed, name: filename.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension } ?? "HTTP requests")
        }
        if let root = try? YAMLObject.parse(trimmed) as? [String: Any] {
            if root["openapi"] != nil || root["swagger"] != nil { return try OpenAPICodec.decode(data) }
            return try CollectionCodec.decode(root: root)
        }
        throw ClientError(unsupportedMessage)
    }

    /// Decodes several files, or a folder such as a Bruno collection, into one import.
    public static func decode(files: [ImportFile], name: String) throws -> CollectionImport {
        guard !files.isEmpty else { throw ClientError("The selection contains no importable files.") }
        let filename = { (file: ImportFile) in (file.path as NSString).lastPathComponent.lowercased() }
        let bruno = files.filter { filename($0).hasSuffix(".bru") || filename($0) == "bruno.json" }
        let brunoFolder = files.contains { filename($0) == "bruno.json" }
        var results: [CollectionImport] = [], warnings: [String] = []
        if bruno.contains(where: { filename($0).hasSuffix(".bru") }) { results.append(try BrunoImport.decode(files: bruno, name: name)) }
        if brunoFolder && files.contains(where: { filename($0) == "opencollection.yml" }) { warnings.append("Bruno YAML (OpenCollection) requests are not imported yet. Save the collection in the .bru format or export it as JSON.") }
        for file in files where !brunoFolder && !bruno.contains(where: { $0.path == file.path }) {
            do { results.append(try decode(file.text, filename: file.path)) } catch { warnings.append("Skipped \(file.path): \(error.localizedDescription)") }
        }
        guard !results.isEmpty else { throw ClientError(warnings.first ?? unsupportedMessage) }
        var merged = merge(results); merged.warnings = unique(warnings + merged.warnings)
        return merged
    }

    static func decoder(for root: [String: Any]) -> (([String: Any]) throws -> CollectionImport)? {
        if let type = root["type"] as? String, type.contains(".insomnia.rest/5") || type.hasPrefix("mcpClient.insomnia") { return InsomniaImport.decodeV5 }
        if let log = root["log"] as? [String: Any], log["entries"] != nil { return har }
        if (root["clientName"] ?? root["client"]) as? String == "Thunder Client" { return thunder }
        if root["version"] as? String == "1", root["items"] is [Any], root["name"] != nil { return BrunoImport.decodeJSON }
        if root["requests"] != nil && root["folders"] != nil && root["v"] != nil { return { try hoppscotch([$0]) } }
        if let requests = root["requests"] as? [[String: Any]], root["order"] != nil || requests.contains(where: { $0["dataMode"] != nil || $0["collectionId"] != nil }) { return postmanV1 }
        if isPostmanDump(root) { return postmanDump }
        if root["variables"] is [[String: Any]], root["name"] != nil, root["requests"] == nil { return { try hoppscotch([$0]) } }
        return nil
    }

    static func isPostmanDump(_ root: [String: Any]) -> Bool {
        guard let collections = root["collections"] as? [[String: Any]] else { return false }
        return collections.contains { $0["order"] != nil || $0["info"] != nil || ($0["requests"] as? [[String: Any]])?.contains { $0["dataMode"] != nil || $0["collectionId"] != nil } == true }
            || (root["environments"] as? [[String: Any]])?.contains { $0["values"] != nil } == true
    }

    static func merge(_ results: [CollectionImport]) -> CollectionImport {
        var workspace = Workspace(), warnings: [String] = []
        for result in results {
            workspace.collections += result.workspace.collections; workspace.environments += result.workspace.environments; warnings += result.warnings
            if let globals = result.workspace.globals, !globals.isEmpty { workspace.globals = (workspace.globals ?? []) + globals }
        }
        return CollectionImport(workspace: workspace, warnings: unique(warnings))
    }

    static func unique(_ values: [String]) -> [String] { var seen = Set<String>(); return values.filter { seen.insert($0).inserted } }
    private static func text(_ value: Any?) -> String { (value as? [Any])?.map { CollectionCodec.string($0) }.joined(separator: "\n") ?? CollectionCodec.string(value) }
    private static func ensureContentType(_ request: inout APIRequest, _ type: String) {
        if !type.isEmpty && !request.headers.contains(where: { $0.name.lowercased() == "content-type" }) { request.headers.append(Field("Content-Type", type)) }
    }
    private static func scriptWarning(_ workspace: Workspace, _ note: String) -> [String] {
        let scripted = workspace.collections.contains { collection in
            collection.requests.contains { !$0.preScript.isEmpty || !$0.postScript.isEmpty } || (collection.folders ?? []).contains { !$0.defaults.preScript.isEmpty || !$0.defaults.postScript.isEmpty }
                || !(collection.defaults?.preScript ?? "").isEmpty || !(collection.defaults?.postScript ?? "").isEmpty
        }
        return scripted ? ["Imported scripts run when you send. " + note] : []
    }
    private static func trimmedScript(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : value }

    // MARK: Postman v1 and data dumps

    static func postmanV1(_ root: [String: Any]) throws -> CollectionImport {
        var warnings: [String] = []
        var collection = RequestCollection(name: root["name"] as? String ?? "Postman collection"), folders: [RequestFolder] = []
        let sources = root["requests"] as? [[String: Any]] ?? []
        let byID = Dictionary(sources.map { (CollectionCodec.string($0["id"]), $0) }, uniquingKeysWith: { first, _ in first })
        let folderSources = root["folders"] as? [[String: Any]] ?? []
        let folderByID = Dictionary(folderSources.map { (CollectionCodec.string($0["id"]), $0) }, uniquingKeysWith: { first, _ in first })
        var placed = Set<String>(), visited = Set<String>()
        func add(_ id: String, folder: UUID?) {
            guard let source = byID[id], placed.insert(id).inserted else { return }
            var request = postmanV1Request(source, warnings: &warnings); request.folderID = folder; collection.requests.append(request)
        }
        func addFolder(_ source: [String: Any], parent: UUID?, depth: Int) {
            guard depth < 32, visited.insert(CollectionCodec.string(source["id"])).inserted else { return }
            var folder = RequestFolder(name: source["name"] as? String ?? "Folder", parentID: parent)
            folder.defaults.description = CollectionCodec.description(source["description"])
            if let auth = source["auth"] as? [String: Any] { folder.defaults.auth = CollectionCodec.decodeAuth(auth, postman: true, warnings: &warnings) }
            folders.append(folder)
            for id in source["order"] as? [String] ?? [] { add(id, folder: folder.id) }
            for id in source["folders_order"] as? [String] ?? [] { if let child = folderByID[id] { addFolder(child, parent: folder.id, depth: depth + 1) } }
        }
        let nested = Set(folderSources.flatMap { $0["folders_order"] as? [String] ?? [] })
        for id in root["order"] as? [String] ?? [] { add(id, folder: nil) }
        let top = (root["folders_order"] as? [String])?.compactMap { folderByID[$0] } ?? folderSources.filter { !nested.contains(CollectionCodec.string($0["id"])) }
        for source in top { addFolder(source, parent: nil, depth: 0) }
        for source in sources where !placed.contains(CollectionCodec.string(source["id"])) { add(CollectionCodec.string(source["id"]), folder: nil) }
        collection.folders = folders.isEmpty ? nil : folders
        var defaults = RequestDefaults(); defaults.description = CollectionCodec.description(root["description"])
        if let auth = root["auth"] as? [String: Any] { defaults.auth = CollectionCodec.decodeAuth(auth, postman: true, warnings: &warnings) }
        defaults.variables = CollectionCodec.fields(root["variables"] as? [[String: Any]] ?? [])
        collection.defaults = defaults
        let workspace = Workspace(collections: [collection])
        return CollectionImport(workspace: workspace, warnings: unique(warnings + scriptWarning(workspace, "Review them in each Scripts tab.")))
    }

    private static func postmanV1Request(_ source: [String: Any], warnings: inout [String]) -> APIRequest {
        var request = APIRequest(name: source["name"] as? String ?? "Untitled", method: (source["method"] as? String ?? "GET").uppercased(), url: CollectionCodec.string(source["url"]))
        request.description = CollectionCodec.description(source["description"])
        if let headers = source["headerData"] as? [[String: Any]] { request.headers = CollectionCodec.fields(headers) }
        else {
            request.headers = (source["headers"] as? String ?? "").split(whereSeparator: \.isNewline).compactMap { line in
                let disabled = line.hasPrefix("//"), body = disabled ? line.dropFirst(2) : Substring(line)
                guard let colon = body.firstIndex(of: ":") else { return nil }
                return Field(body[..<colon].trimmingCharacters(in: .whitespaces), body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces), enabled: !disabled)
            }
        }
        if let query = source["queryParams"] as? [[String: Any]], !query.isEmpty { request.query = CollectionCodec.fields(query); request.url = CollectionCodec.withoutQuery(request.url) }
        if let path = source["pathVariableData"] as? [[String: Any]], !path.isEmpty { request.pathVariables = CollectionCodec.fields(path) }
        let data = source["data"] as? [[String: Any]] ?? []
        switch source["dataMode"] as? String {
        case "raw":
            request.body = source["rawModeData"] as? String ?? ""
            let type = request.headers.first { $0.name.lowercased() == "content-type" }?.value ?? ""
            request.bodyKind = type.contains("json") || (type.isEmpty && (try? JSONSerialization.jsonObject(with: Data(request.body.utf8))) is [String: Any]) ? .json : .text
        case "urlencoded": request.bodyKind = .form; request.form = CollectionCodec.fields(data)
        case "params":
            request.bodyKind = .multipart
            request.multipart = data.map { field in
                MultipartPart(name: CollectionCodec.string(field["key"]), value: field["type"] as? String == "file" ? "" : CollectionCodec.string(field["value"]), enabled: field["enabled"] as? Bool ?? true,
                              file: field["type"] as? String == "file" ? RequestFile(filename: CollectionCodec.string(field["value"])) : nil)
            }
            if request.multipart?.contains(where: { $0.file != nil }) == true { warnings.append("Choose imported attachment files on this device before sending.") }
        case "binary": request.bodyKind = .file; request.fileBody = RequestFile(filename: "body"); warnings.append("Choose the imported body file on this device before sending.")
        case "graphql":
            let graph = source["graphqlModeData"] as? [String: Any] ?? [:]
            var graphql = GraphQLRequest(); graphql.query = graph["query"] as? String ?? ""; graphql.variables = (graph["variables"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "{}"
            request.transport = .graphql; request.graphql = graphql; request.bodyKind = .json
            request.body = String(decoding: (try? CollectionCodec.json(["query": graphql.query])) ?? Data(), as: UTF8.self)
        default: break
        }
        if let auth = source["auth"] as? [String: Any] { request.auth = CollectionCodec.decodeAuth(auth, postman: true, warnings: &warnings) }
        else {
            let helper = source["helperAttributes"] as? [String: Any] ?? [:]
            switch source["currentHelper"] as? String {
            case "basicAuth": request.auth.kind = .basic; request.auth.username = CollectionCodec.string(helper["username"]); request.auth.password = CollectionCodec.string(helper["password"])
            case "digestAuth": request.auth.kind = .digest; request.auth.username = CollectionCodec.string(helper["username"]); request.auth.password = CollectionCodec.string(helper["password"])
            case "bearerAuth": request.auth.kind = .bearer; request.auth.token = CollectionCodec.string(helper["token"])
            case nil, "normal", "": request.auth.kind = .inherit
            case let other?: warnings.append("Postman v1 helper ‘\(other)’ is unsupported. Configure authentication manually.")
            }
        }
        request.preScript = trimmedScript(source["preRequestScript"] as? String ?? "")
        request.postScript = trimmedScript(source["tests"] as? String ?? "")
        let examples = (source["responses"] as? [[String: Any]] ?? []).prefix(ResponseExample.maximumCount).compactMap { response -> ResponseExample? in
            let body = response["text"] as? String ?? ""
            guard body.utf8.count <= ResponseExample.maximumBodyBytes else { return nil }
            let code = (response["responseCode"] as? [String: Any])?["code"] as? Int ?? 200
            return ResponseExample(name: response["name"] as? String ?? "Example", status: code, headers: CollectionCodec.fields(response["headers"] as? [[String: Any]] ?? []), body: body)
        }
        if !examples.isEmpty { request.examples = examples }
        return request
    }

    static func postmanDump(_ root: [String: Any]) throws -> CollectionImport {
        var results: [CollectionImport] = []
        for collection in root["collections"] as? [[String: Any]] ?? [] {
            results.append(try collection["info"] != nil && collection["item"] != nil ? CollectionCodec.postman(collection) : postmanV1(collection))
        }
        var workspace = Workspace()
        workspace.environments = (root["environments"] as? [[String: Any]] ?? []).map { APIEnvironment(name: $0["name"] as? String ?? "Environment", variables: CollectionCodec.fields($0["values"] as? [[String: Any]] ?? [])) }
        let globals = root["globals"] as? [[String: Any]] ?? ((root["globals"] as? [String: Any])?["values"] as? [[String: Any]]) ?? []
        if !globals.isEmpty { workspace.globals = CollectionCodec.fields(globals) }
        results.append(CollectionImport(workspace: workspace))
        return merge(results)
    }

    // MARK: HAR

    static func har(_ root: [String: Any]) throws -> CollectionImport {
        let entries = ((root["log"] as? [String: Any])?["entries"] as? [[String: Any]] ?? [])
        guard entries.count <= 5000 else { throw ClientError("HAR files can contain at most 5,000 requests.") }
        var collection = RequestCollection(name: "HAR import"), folders: [String: UUID] = [:], warnings: [String] = []
        let skipped: Set = ["content-length", "host", "connection", "accept-encoding", "transfer-encoding", "keep-alive", "upgrade"]
        for entry in entries {
            guard let source = entry["request"] as? [String: Any], let url = source["url"] as? String, let components = URLComponents(string: url), let host = components.host else { continue }
            if url.hasPrefix("data:") || url.hasPrefix("blob:") { continue }
            let path = components.path.isEmpty ? "/" : components.path
            var request = APIRequest(name: "\((source["method"] as? String ?? "GET").uppercased()) \(path)", method: (source["method"] as? String ?? "GET").uppercased(), url: url)
            request.headers = (source["headers"] as? [[String: Any]] ?? []).compactMap { header in
                let name = CollectionCodec.string(header["name"])
                return name.hasPrefix(":") || skipped.contains(name.lowercased()) ? nil : Field(name, CollectionCodec.string(header["value"]))
            }
            if let post = source["postData"] as? [String: Any] {
                let mime = post["mimeType"] as? String ?? "", params = post["params"] as? [[String: Any]] ?? []
                if mime.contains("x-www-form-urlencoded") && !params.isEmpty {
                    request.bodyKind = .form
                    request.form = params.map { Field(($0["name"] as? String ?? "").removingPercentEncoding ?? "", (CollectionCodec.string($0["value"]).replacingOccurrences(of: "+", with: " ")).removingPercentEncoding ?? "") }
                } else if mime.contains("multipart") && !params.isEmpty {
                    request.bodyKind = .multipart
                    request.multipart = params.map { param in
                        MultipartPart(name: CollectionCodec.string(param["name"]), value: param["fileName"] == nil ? CollectionCodec.string(param["value"]) : "",
                                      file: param["fileName"].map { RequestFile(filename: CollectionCodec.string($0), mimeType: param["contentType"] as? String ?? "application/octet-stream") })
                    }
                    request.headers.removeAll { $0.name.lowercased() == "content-type" }
                    if request.multipart?.contains(where: { $0.file != nil }) == true { warnings.append("Choose imported attachment files on this device before sending.") }
                } else if let text = post["text"] as? String, !text.isEmpty {
                    request.bodyKind = mime.contains("json") ? .json : .text; request.body = text
                    ensureContentType(&request, mime)
                }
            }
            if let response = entry["response"] as? [String: Any], let content = response["content"] as? [String: Any], let body = content["text"] as? String,
               content["encoding"] as? String != "base64", body.utf8.count <= ResponseExample.maximumBodyBytes, let status = response["status"] as? Int, (100...599).contains(status) {
                let headers = (response["headers"] as? [[String: Any]] ?? []).map { Field(CollectionCodec.string($0["name"]), CollectionCodec.string($0["value"])) }
                    .filter { !["content-length", "content-encoding", "transfer-encoding", "connection"].contains($0.name.lowercased()) }
                request.examples = [ResponseExample(name: "Recorded response", status: status, headers: headers, body: body)]
            }
            if folders[host] == nil { let folder = RequestFolder(name: host); folders[host] = folder.id; collection.folders = (collection.folders ?? []) + [folder] }
            request.folderID = folders[host]
            collection.requests.append(request)
        }
        guard !collection.requests.isEmpty else { throw ClientError("The HAR file contains no HTTP requests.") }
        if collection.requests.contains(where: { $0.headers.contains { ["cookie", "authorization"].contains($0.name.lowercased()) } }) { warnings.append("Recorded Cookie and Authorization headers were imported. Remove them if the session has expired.") }
        return CollectionImport(workspace: Workspace(collections: [collection]), warnings: unique(warnings))
    }

    // MARK: Thunder Client

    private static func thunderValue(_ value: String) -> String {
        let dynamic = ["guid": "$guid", "uuid": "$randomUUID", "timestamp": "$timestamp", "date": "$isoTimestamp", "number": "$randomInt", "bool": "$randomBoolean", "string": "$randomAlphaNumeric", "email": "$randomEmail", "name": "$randomFullName"]
        let pattern = try! NSRegularExpression(pattern: #"\{\{#(\w+)[^}]*\}\}"#)
        var result = value
        for match in pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: value), let nameRange = Range(match.range(at: 1), in: value), let name = dynamic[String(value[nameRange])] else { continue }
            result.replaceSubrange(range, with: "{{\(name)}}")
        }
        return result
    }
    private static func thunderFields(_ source: Any?) -> [Field] {
        (source as? [[String: Any]] ?? []).map { Field(thunderValue(CollectionCodec.string($0["name"])), thunderValue(CollectionCodec.string($0["value"])), enabled: !($0["isDisabled"] as? Bool ?? false)) }
    }
    private static func thunderAuth(_ source: Any?, warnings: inout [String]) -> RequestAuth {
        var auth = RequestAuth()
        guard let source = source as? [String: Any], let type = source["type"] as? String else { auth.kind = .inherit; return auth }
        switch type {
        case "inherit": auth.kind = .inherit
        case "none": break
        case "bearer": auth.kind = .bearer; auth.token = thunderValue(CollectionCodec.string(source["bearer"]))
            if let prefix = source["bearerPrefix"] as? String, !prefix.isEmpty, prefix != "Bearer" { warnings.append("Bearer prefix ‘\(prefix)’ was replaced by Bearer. Use an Authorization header to keep it.") }
        case "basic", "ntlm":
            let basic = source[type] as? [String: Any] ?? [:]
            auth.kind = .basic; auth.username = thunderValue(CollectionCodec.string(basic["username"])); auth.password = thunderValue(CollectionCodec.string(basic["password"]))
            if type == "ntlm" { warnings.append("NTLM authentication is unsupported; Basic is used instead.") }
        case "oauth2", "aws":
            var values = source[type] as? [String: Any] ?? [:]; values["type"] = type
            auth = CollectionCodec.decodeAuth(values, postman: false, warnings: &warnings)
        default: warnings.append("Thunder Client authentication ‘\(type)’ is unsupported. Configure it manually.")
        }
        return auth
    }
    /// Converts Thunder Client's declarative tests into scripts that use the `tc` helper.
    static func thunderTests(_ source: Any?, warnings: inout [String]) -> String {
        func quoted(_ value: String) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)) ?? Data("\"\"".utf8), as: UTF8.self) }
        return (source as? [[String: Any]] ?? []).compactMap { test -> String? in
            let type = CollectionCodec.string(test["type"]), custom = CollectionCodec.string(test["custom"]), action = CollectionCodec.string(test["action"]), value = CollectionCodec.string(test["value"])
            let read: String
            switch type.lowercased() {
            case "res-code": read = "tc.response.status"
            case "res-body": read = "tc.response.text"
            case "res-time": read = "tc.response.time"
            case "json-query", "set-env-var": read = custom.hasPrefix("json") ? "{ const json = tc.response.json; return \(custom); }" : "pm.response.headers.get(\(quoted(custom.replacingOccurrences(of: "header.", with: ""))))"
            case "content-type", "content-length", "content-encoding": read = "pm.response.headers.get(\(quoted(type)))"
            case "header", "custom-header": read = "pm.response.headers.get(\(quoted(custom)))"
            default: warnings.append("Thunder Client test type ‘\(type)’ was not converted."); return nil
            }
            let body = read.hasPrefix("{") ? read : "{ return \(read); }"
            if type.lowercased() == "set-env-var" {
                let name = value.replacingOccurrences(of: "{{", with: "").replacingOccurrences(of: "}}", with: "").trimmingCharacters(in: .whitespaces)
                return "try { tc.setVar(\(quoted(name)), (() => \(body))()); } catch (e) { console.warn('Could not set \(name): ' + e.message); }"
            }
            return "tc.check(\(quoted([type, custom, action, value].filter { !$0.isEmpty }.joined(separator: " "))), () => \(body), \(quoted(action)), \(quoted(value)));"
        }.joined(separator: "\n")
    }
    private static func thunderScripts(_ source: Any?) -> String {
        ((source as? [String: Any])?["inlineScripts"] as? [[String: Any]] ?? []).map { text($0["script"]) }.joined(separator: "\n")
    }
    private static func thunderDefaults(_ settings: [String: Any]?, inherit: Bool, warnings: inout [String]) -> RequestDefaults {
        var defaults = RequestDefaults()
        defaults.headers = thunderFields(settings?["headers"])
        defaults.auth = thunderAuth(settings?["auth"], warnings: &warnings)
        if defaults.auth.kind == .inherit && !inherit { defaults.auth.kind = .none }
        defaults.preScript = thunderScripts(settings?["preReq"])
        defaults.postScript = [thunderTests(settings?["tests"], warnings: &warnings), thunderScripts(settings?["postReq"])].filter { !$0.isEmpty }.joined(separator: "\n")
        defaults.variables = thunderFields(settings?["variables"])
        return defaults
    }

    static func thunder(_ root: [String: Any]) throws -> CollectionImport {
        if root["requests"] == nil, let variables = root["variables"] {
            var workspace = Workspace()
            if root["global"] as? Bool == true { workspace.globals = thunderFields(variables) }
            else { workspace.environments = [APIEnvironment(name: root["environmentName"] as? String ?? "Thunder Client environment", variables: thunderFields(variables))] }
            return CollectionImport(workspace: workspace)
        }
        var warnings: [String] = []
        var collection = RequestCollection(name: root["collectionName"] as? String ?? "Thunder Client collection")
        let settings = root["settings"] as? [String: Any]
        let base = CollectionCodec.string((settings?["options"] as? [String: Any])?["baseUrl"])
        let order = { (a: [String: Any], b: [String: Any]) in ((a["sortNum"] as? NSNumber)?.doubleValue ?? .infinity) < ((b["sortNum"] as? NSNumber)?.doubleValue ?? .infinity) }
        let folderSources = (root["folders"] as? [[String: Any]] ?? []).sorted(by: order)
        var folderIDs: [String: UUID] = [:]
        for source in folderSources { folderIDs[CollectionCodec.string(source["_id"])] = UUID() }
        collection.folders = folderSources.isEmpty ? nil : folderSources.map { source in
            var folder = RequestFolder(name: source["name"] as? String ?? "Folder", parentID: folderIDs[CollectionCodec.string(source["containerId"])])
            folder.id = folderIDs[CollectionCodec.string(source["_id"])]!
            folder.defaults = thunderDefaults(source["settings"] as? [String: Any], inherit: true, warnings: &warnings)
            return folder
        }
        for source in (root["requests"] as? [[String: Any]] ?? []).sorted(by: order) {
            let params = source["params"] as? [[String: Any]] ?? []
            let pathNames = params.filter { $0["isPath"] as? Bool == true }.map { CollectionCodec.string($0["name"]) }
            var url = thunderValue(CollectionCodec.string(source["url"]))
            for name in pathNames { url = url.replacingOccurrences(of: "{\(name)}", with: ":\(name)") }
            let absolute = url.range(of: #"^(\w+://|\{\{)"#, options: .regularExpression) != nil
            if !absolute && !base.isEmpty { url = (base.hasSuffix("/") ? String(base.dropLast()) : base) + (url.hasPrefix("/") ? url : "/" + url) }
            var request = APIRequest(name: source["name"] as? String ?? "Untitled", method: (source["method"] as? String ?? "GET").uppercased(), url: params.contains { $0["isPath"] as? Bool != true } ? CollectionCodec.withoutQuery(url) : url)
            request.folderID = folderIDs[CollectionCodec.string(source["containerId"])]
            request.headers = thunderFields(source["headers"])
            let query = params.filter { $0["isPath"] as? Bool != true }, path = params.filter { $0["isPath"] as? Bool == true }
            if !query.isEmpty { request.query = thunderFields(query) }
            if !path.isEmpty { request.pathVariables = thunderFields(path) }
            request.description = CollectionCodec.description(text(source["docs"]))
            switch source["reqType"] as? String { case "ws": request.transport = .websocket; case "sse": request.transport = .sse; default: break }
            let body = source["body"] as? [String: Any] ?? [:], raw = thunderValue(text(body["raw"]))
            switch body["type"] as? String {
            case "json": request.bodyKind = .json; request.body = raw; ensureContentType(&request, "application/json")
            case "text": request.bodyKind = .text; request.body = raw; ensureContentType(&request, "text/plain")
            case "xml": request.bodyKind = .text; request.body = raw; ensureContentType(&request, "application/xml")
            case "formencoded": request.bodyKind = .form; request.form = thunderFields(body["form"])
            case "formdata":
                request.bodyKind = .multipart
                request.multipart = thunderFields(body["form"]).map { MultipartPart(name: $0.name, value: $0.value, enabled: $0.enabled) }
                    + (body["files"] as? [[String: Any]] ?? []).map { MultipartPart(name: CollectionCodec.string($0["name"]), enabled: !($0["isDisabled"] as? Bool ?? false), file: RequestFile(filename: (CollectionCodec.string($0["value"]) as NSString).lastPathComponent)) }
                if request.multipart?.contains(where: { $0.file != nil }) == true { warnings.append("Choose imported attachment files on this device before sending.") }
            case "graphql":
                let graph = body["graphql"] as? [String: Any] ?? [:]
                var graphql = GraphQLRequest(); graphql.query = thunderValue(CollectionCodec.string(graph["query"])); graphql.variables = CollectionCodec.string(graph["variables"]).isEmpty ? "{}" : thunderValue(CollectionCodec.string(graph["variables"]))
                request.transport = .graphql; request.graphql = graphql; request.bodyKind = .json
                request.body = String(decoding: (try? CollectionCodec.json(["query": graphql.query])) ?? Data(), as: UTF8.self); ensureContentType(&request, "application/json")
            case "binary": request.bodyKind = .file; request.fileBody = RequestFile(filename: (CollectionCodec.string(body["binary"]) as NSString).lastPathComponent); warnings.append("Choose the imported body file on this device before sending.")
            default: break
            }
            request.auth = thunderAuth(source["auth"], warnings: &warnings)
            request.preScript = thunderScripts(source["preReq"])
            request.postScript = [thunderTests(source["tests"], warnings: &warnings), thunderScripts(source["postReq"])].filter { !$0.isEmpty }.joined(separator: "\n")
            if (source["preReq"] as? [String: Any])?["runRequests"] != nil { warnings.append("Thunder Client ‘run request before’ steps were not imported. Use a collection run instead.") }
            collection.requests.append(request)
        }
        collection.defaults = thunderDefaults(settings, inherit: false, warnings: &warnings)
        let workspace = Workspace(collections: [collection])
        return CollectionImport(workspace: workspace, warnings: unique(warnings + scriptWarning(workspace, "Thunder Client tests were converted to scripts that use tc and pm.")))
    }

    // MARK: Hoppscotch

    private static func hopp(_ value: String) -> String { value.replacingOccurrences(of: #"<<\s*([\w.\-]+)\s*>>"#, with: "{{$1}}", options: .regularExpression) }
    private static func hoppFields(_ source: Any?) -> [Field] {
        (source as? [[String: Any]] ?? []).map { Field(hopp(CollectionCodec.string($0["key"] ?? $0["name"])), hopp(CollectionCodec.string($0["value"])), enabled: $0["active"] as? Bool ?? $0["enabled"] as? Bool ?? true) }
    }
    private static func hoppVariables(_ source: Any?) -> [Field] {
        (source as? [[String: Any]] ?? []).map { item in
            let current = CollectionCodec.string(item["currentValue"]), value = item["value"] != nil ? CollectionCodec.string(item["value"]) : current.isEmpty ? CollectionCodec.string(item["initialValue"]) : current
            var field = Field(CollectionCodec.string(item["key"] ?? item["name"]), hopp(value), enabled: item["enabled"] as? Bool ?? item["active"] as? Bool ?? true)
            if let secret = item["secret"] as? Bool, secret { field.secret = true }
            return field
        }
    }
    private static func hoppAuth(_ source: Any?, warnings: inout [String]) -> RequestAuth {
        var auth = RequestAuth()
        guard let source = source as? [String: Any], let type = source["authType"] as? String else { auth.kind = .inherit; return auth }
        if source["authActive"] as? Bool == false && type != "inherit" { return auth }
        let value = { (key: String) in hopp(CollectionCodec.string(source[key])) }
        switch type {
        case "inherit": auth.kind = .inherit
        case "none": break
        case "basic": auth.kind = .basic; auth.username = value("username"); auth.password = value("password")
        case "digest": auth.kind = .digest; auth.username = value("username"); auth.password = value("password")
        case "bearer": auth.kind = .bearer; auth.token = value("token")
        case "api-key":
            var key = APIKeyAuth(); key.name = value("key"); key.value = value("value"); key.inQuery = value("addTo").uppercased().contains("QUERY"); auth.kind = .apiKey; auth.apiKey = key
        case "aws-signature":
            var aws = AWSAuth(); aws.accessKey = value("accessKey"); aws.secretKey = value("secretKey"); aws.region = value("region"); aws.service = value("serviceName"); aws.sessionToken = value("serviceToken")
            auth.kind = .aws; auth.aws = aws
        case "jwt":
            var jwt = JWTAuth(); jwt.algorithm = JWTAlgorithm(rawValue: value("algorithm")) ?? .hs256; jwt.secret = value("secret"); jwt.privateKey = value("privateKey")
            jwt.payload = value("payload").isEmpty ? "{}" : value("payload"); jwt.header = value("jwtHeaders").isEmpty ? "{}" : value("jwtHeaders"); jwt.secretIsBase64 = source["isSecretBase64Encoded"] as? Bool ?? false
            jwt.inQuery = value("addTo") == "QUERY_PARAMS"; jwt.headerPrefix = value("headerPrefix").trimmingCharacters(in: .whitespaces); jwt.queryKey = value("paramName").isEmpty ? "token" : value("paramName")
            auth.kind = .jwt; auth.jwt = jwt
        case "oauth-2":
            let info = source["grantTypeInfo"] as? [String: Any] ?? [:]
            var oauth = OAuthConfiguration(); let grant = CollectionCodec.string(info["grantType"])
            oauth.grant = ["CLIENT_CREDENTIALS": .clientCredentials, "PASSWORD": .password][grant] ?? .pkce
            oauth.authorizationURL = hopp(CollectionCodec.string(info["authEndpoint"])); oauth.tokenURL = hopp(CollectionCodec.string(info["tokenEndpoint"] ?? info["authEndpoint"]))
            oauth.clientID = hopp(CollectionCodec.string(info["clientID"])); oauth.clientSecret = hopp(CollectionCodec.string(info["clientSecret"])); oauth.scope = hopp(CollectionCodec.string(info["scopes"]))
            oauth.accessToken = CollectionCodec.string(info["token"])
            if oauth.grant == .password { oauth.username = hopp(CollectionCodec.string(info["username"])); oauth.password = hopp(CollectionCodec.string(info["password"])) }
            if grant == "IMPLICIT" { warnings.append("OAuth 2.0 implicit grants are imported as authorization code with PKCE.") }
            auth.kind = .oauth2; auth.oauth = oauth
        default: warnings.append("Hoppscotch authentication ‘\(type)’ is unsupported. Configure it manually.")
        }
        return auth
    }
    private static func hoppRequest(_ source: [String: Any], warnings: inout [String]) -> APIRequest {
        let graphQL = source["endpoint"] == nil && source["query"] != nil
        var request = APIRequest(name: source["name"] as? String ?? "Untitled", method: graphQL ? "POST" : (source["method"] as? String ?? "GET").uppercased(), url: hopp(CollectionCodec.string(source["endpoint"] ?? source["url"])))
        request.headers = hoppFields(source["headers"]); request.query = hoppFields(source["params"])
        request.auth = hoppAuth(source["auth"], warnings: &warnings)
        request.description = CollectionCodec.description(source["description"])
        let variables = hoppFields(source["requestVariables"]); if !variables.isEmpty { request.variables = variables }
        request.preScript = trimmedScript(source["preRequestScript"] as? String ?? ""); request.postScript = trimmedScript(source["testScript"] as? String ?? "")
        if graphQL {
            var graphql = GraphQLRequest(); graphql.query = hopp(CollectionCodec.string(source["query"])); graphql.variables = CollectionCodec.string(source["variables"]).isEmpty ? "{}" : hopp(CollectionCodec.string(source["variables"]))
            request.transport = .graphql; request.graphql = graphql; request.bodyKind = .json
            request.body = String(decoding: (try? CollectionCodec.json(["query": graphql.query])) ?? Data(), as: UTF8.self); ensureContentType(&request, "application/json")
            return request
        }
        let body = source["body"] as? [String: Any] ?? [:], type = body["contentType"] as? String ?? ""
        switch type {
        case "": break
        case "multipart/form-data":
            request.bodyKind = .multipart
            request.multipart = (body["body"] as? [[String: Any]] ?? []).map { field in
                let file = field["isFile"] as? Bool == true
                return MultipartPart(name: hopp(CollectionCodec.string(field["key"])), value: file ? "" : hopp(CollectionCodec.string(field["value"])), enabled: field["active"] as? Bool ?? true,
                                     file: file ? RequestFile(filename: CollectionCodec.string(field["key"]), mimeType: field["contentType"] as? String ?? "application/octet-stream") : nil)
            }
            if request.multipart?.contains(where: { $0.file != nil }) == true { warnings.append("Choose imported attachment files on this device before sending.") }
        case "application/x-www-form-urlencoded":
            request.bodyKind = .form
            request.form = CollectionCodec.string(body["body"]).split(whereSeparator: \.isNewline).compactMap { line in
                let disabled = line.hasPrefix("#"), entry = disabled ? line.dropFirst() : Substring(line)
                guard let colon = entry.firstIndex(of: ":") else { return nil }
                return Field(hopp(entry[..<colon].trimmingCharacters(in: .whitespaces)), hopp(entry[entry.index(after: colon)...].trimmingCharacters(in: .whitespaces)), enabled: !disabled)
            }
        case "application/octet-stream": request.bodyKind = .file; request.fileBody = RequestFile(filename: "body"); warnings.append("Choose the imported body file on this device before sending.")
        default:
            request.bodyKind = type.contains("json") ? .json : .text; request.body = hopp(CollectionCodec.string(body["body"]))
            ensureContentType(&request, type == "binary" ? "application/octet-stream" : type)
        }
        if let responses = source["responses"] as? [String: Any] {
            let examples = responses.keys.sorted().prefix(ResponseExample.maximumCount).compactMap { key -> ResponseExample? in
                guard let response = responses[key] as? [String: Any], let text = response["body"] as? String, text.utf8.count <= ResponseExample.maximumBodyBytes else { return nil }
                return ResponseExample(name: response["name"] as? String ?? key, status: response["code"] as? Int ?? 200, headers: hoppFields(response["headers"]), body: text)
            }
            if !examples.isEmpty { request.examples = examples }
        }
        return request
    }

    static func hoppscotch(_ list: [[String: Any]]) throws -> CollectionImport {
        var warnings: [String] = [], workspace = Workspace()
        for item in list {
            if item["requests"] == nil && item["folders"] == nil {
                guard item["variables"] != nil else { throw ClientError(unsupportedMessage) }
                workspace.environments.append(APIEnvironment(name: item["name"] as? String ?? "Environment", variables: hoppVariables(item["variables"])))
                continue
            }
            var collection = RequestCollection(name: item["name"] as? String ?? "Hoppscotch collection"), folders: [RequestFolder] = []
            func defaults(_ source: [String: Any], inherit: Bool) -> RequestDefaults {
                var defaults = RequestDefaults(); defaults.headers = hoppFields(source["headers"]); defaults.variables = hoppVariables(source["variables"])
                defaults.auth = hoppAuth(source["auth"], warnings: &warnings); if defaults.auth.kind == .inherit && !inherit { defaults.auth.kind = .none }
                defaults.preScript = trimmedScript(source["preRequestScript"] as? String ?? ""); defaults.postScript = trimmedScript(source["testScript"] as? String ?? "")
                defaults.description = CollectionCodec.description(source["description"])
                return defaults
            }
            func walk(_ source: [String: Any], parent: UUID?, depth: Int) throws {
                guard depth < 32, folders.count < 2000 else { throw ClientError("Hoppscotch folders exceed the depth or count limit.") }
                for request in source["requests"] as? [[String: Any]] ?? [] { var value = hoppRequest(request, warnings: &warnings); value.folderID = parent; collection.requests.append(value) }
                for child in source["folders"] as? [[String: Any]] ?? [] {
                    var folder = RequestFolder(name: child["name"] as? String ?? "Folder", parentID: parent); folder.defaults = defaults(child, inherit: true)
                    folders.append(folder); try walk(child, parent: folder.id, depth: depth + 1)
                }
            }
            try walk(item, parent: nil, depth: 0)
            collection.folders = folders.isEmpty ? nil : folders; collection.defaults = defaults(item, inherit: false)
            workspace.collections.append(collection)
        }
        return CollectionImport(workspace: workspace, warnings: unique(warnings + scriptWarning(workspace, "Hoppscotch pw and hopp scripts are supported for environment, test, expect and response.")))
    }
}

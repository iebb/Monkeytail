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
        guard data.count <= 40 * 1024 * 1024 else { throw ClientError("Import files must be smaller than 40 MB.") }
        let object = try JSONSerialization.jsonObject(with: data)
        if let list = object as? [[String: Any]] { return try InterchangeImport.hoppscotch(list) }
        guard let root = object as? [String: Any] else { throw ClientError("Choose a JSON collection or environment file.") }
        if root["collections"] != nil && root["version"] != nil && !InterchangeImport.isPostmanDump(root) {
            let workspace = try JSONDecoder().decode(Workspace.self, from: data)
            guard workspace.version == 1 else { throw ClientError("This Monkeytail file uses an unsupported version.") }
            return CollectionImport(workspace: workspace, includesSettings: true)
        }
        return try decode(root: root)
    }

    /// Decodes a third-party collection, environment or export parsed from JSON or YAML.
    static func decode(root: [String: Any]) throws -> CollectionImport {
        if root["info"] != nil && root["item"] != nil { return try postman(root) }
        if let format = InterchangeImport.decoder(for: root) { return try format(root) }
        if let values = root["values"] as? [[String: Any]] {
            if root["_postman_variable_scope"] as? String == "globals" {
                var workspace = Workspace(); workspace.globals = fields(values)
                return CollectionImport(workspace: workspace)
            }
            return CollectionImport(workspace: Workspace(environments: [APIEnvironment(name: root["name"] as? String ?? "Imported environment", variables: fields(values))]))
        }
        if let resources = root["resources"] as? [[String: Any]] { return try InsomniaImport.decode(root, resources: resources) }
        throw ClientError(verbatim: InterchangeImport.unsupportedMessage)
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
                "item": workspace.collections.map(postmanCollection)
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
                    case .multipart: body = ["mimeType": "multipart/form-data", "params": (request.multipart ?? []).map { part in
                        var field: [String: Any] = ["name": part.name, "value": part.value, "disabled": !part.enabled, "type": part.file == nil ? "text" : "file"]
                        if let file = part.file { field["fileName"] = file.filename; field["contentType"] = file.mimeType }
                        return field
                    }]
                    case .file: body = ["mimeType": request.fileBody?.mimeType ?? "application/octet-stream", "fileName": request.fileBody?.filename ?? ""]
                    }
                    var auth: [String: Any] = [:]
                    if request.auth.kind == .bearer { auth = ["type": "bearer", "token": request.auth.token] }
                    if request.auth.kind == .basic || request.auth.kind == .digest { auth = ["type": request.auth.kind == .basic ? "basic" : "digest", "username": request.auth.username, "password": request.auth.password] }
                    resources.append(["_id": "req_" + request.id.uuidString, "_type": "request", "parentId": groupID, "name": request.name, "url": request.url, "method": request.method, "description": request.description ?? "",
                                      "headers": request.headers.map(insomniaField), "parameters": request.query.map(insomniaField), "body": body, "authentication": auth,
                                      "settingFollowRedirects": request.followRedirects ? "on" : "off", "preRequestScript": request.preScript, "afterResponseScript": request.postScript,
                                      "_monkeytail": transportMetadata(request)])
                }
            }
            return try json(["_type": "export", "__export_format": 4, "__export_date": ISO8601DateFormatter().string(from: Date()), "__export_source": "monkeytail:1.0", "resources": resources])
        }
    }

    static func postman(_ root: [String: Any]) throws -> CollectionImport {
        var requests: [APIRequest] = [], warnings: [String] = [], folders: [RequestFolder] = []
        func walk(_ items: [[String: Any]], path: String, inheritedAuth: [String: Any]?, inheritedEvents: [[String: Any]], parent: UUID?) throws {
            for item in items {
                let name = item["name"] as? String ?? "Untitled"
                guard folders.count < 2000, path.count < 32 else { throw ClientError("Postman folders exceed the depth or count limit.") }
                if let children = item["item"] as? [[String: Any]] {
                    var folder = RequestFolder(name: name, parentID: parent)
                    folder.defaults = decodeDefaults(item, warnings: &warnings, inherit: true)
                    folders.append(folder)
                    try walk(children, path: path + "/", inheritedAuth: nil, inheritedEvents: [], parent: folder.id)
                    continue
                }
                let source = item["request"] as? [String: Any] ?? ["url": item["request"] as? String ?? ""]
                let urlObject = source["url"] as? [String: Any]
                let raw = source["url"] as? String ?? urlObject?["raw"] as? String ?? ""
                guard !raw.isEmpty else { throw ClientError("Request ‘\(name)’ is missing a raw URL.") }
                var request = APIRequest(name: name, method: source["method"] as? String ?? "GET", url: raw)
                request.folderID = parent
                request.description = description(source["description"]) ?? description(item["description"])
                request.impersonation = try decodeTransport(item["_monkeytail"])
                decodeAdvanced(item["_monkeytail"], into: &request)
                request.headers = fields(source["header"] as? [[String: Any]] ?? [])
                if let query = urlObject?["query"] as? [[String: Any]] {
                    request.query = fields(query)
                    request.url = withoutQuery(raw)
                }
                if let variables = urlObject?["variable"] as? [[String: Any]], !variables.isEmpty { request.pathVariables = fields(variables) }
                if let sourceAuth = source["auth"] as? [String: Any] { request.auth = decodeAuth(sourceAuth, postman: true, warnings: &warnings) }
                else { request.auth.kind = .inherit }
                if let metadata = item["_monkeytail"] as? [String: Any], let value = metadata["auth"], let data = try? json(value), let restored = try? JSONDecoder().decode(RequestAuth.self, from: data) { request.auth = restored }
                if let body = source["body"] as? [String: Any] {
                    switch body["mode"] as? String {
                    case "raw":
                        request.body = body["raw"] as? String ?? ""
                        let options = body["options"] as? [String: Any]
                        let language = (options?["raw"] as? [String: Any])?["language"] as? String
                        request.bodyKind = language == "json" || request.headers.contains { $0.name.lowercased() == "content-type" && $0.value.contains("json") } ? .json : .text
                        // Postman sends a Content-Type matching the raw language.
                        if let type = ["xml": "application/xml", "html": "text/html", "javascript": "application/javascript"][language ?? ""], !request.headers.contains(where: { $0.name.lowercased() == "content-type" }) {
                            request.headers.append(Field("Content-Type", type))
                        }
                    case "urlencoded": request.bodyKind = .form; request.form = fields(body["urlencoded"] as? [[String: Any]] ?? [])
                    case "formdata":
                        request.bodyKind = .multipart
                        request.multipart = (body["formdata"] as? [[String: Any]] ?? []).flatMap { field -> [MultipartPart] in
                            let paths = field["src"] as? [String] ?? [field["src"] as? String ?? ""]
                            if field["type"] as? String == "file" {
                                return paths.map { MultipartPart(name: string(field["key"]), enabled: !(field["disabled"] as? Bool ?? false), file: RequestFile(filename: $0, mimeType: field["contentType"] as? String ?? "application/octet-stream")) }
                            }
                            return [MultipartPart(name: string(field["key"]), value: string(field["value"]), enabled: !(field["disabled"] as? Bool ?? false))]
                        }
                        warnings.append(String(localized: "Choose imported attachment files on this device before sending.", bundle: .module))
                    case "file":
                        request.bodyKind = .file
                        request.fileBody = RequestFile(filename: string((body["file"] as? [String: Any])?["src"]))
                        warnings.append(String(localized: "Choose the imported body file on this device before sending.", bundle: .module))
                    case "graphql":
                        request.bodyKind = .json
                        request.transport = .graphql
                        let graph = body["graphql"] as? [String: Any] ?? [:]
                        var payload: [String: Any] = ["query": graph["query"] as? String ?? ""]
                        if let variables = graph["variables"] as? String, !variables.isEmpty { payload["variables"] = try JSONTools.parse(variables) }
                        request.body = String(decoding: try json(payload), as: UTF8.self)
                        var graphql = GraphQLRequest(); graphql.query = graph["query"] as? String ?? ""; graphql.variables = graph["variables"] as? String ?? "{}"; request.graphql = graphql
                    case nil: break
                    default: throw ClientError("‘\(name)’ uses an unsupported body mode. Use raw, urlencoded, formdata, file, or GraphQL bodies.")
                    }
                }
                for event in item["event"] as? [[String: Any]] ?? [] {
                    let script = event["script"] as? [String: Any]
                    let code = (script?["exec"] as? [String])?.joined(separator: "\n") ?? script?["exec"] as? String ?? ""
                    if event["listen"] as? String == "prerequest" { request.preScript += code + "\n" }
                    if event["listen"] as? String == "test" { request.postScript += code + "\n" }
                }
                let examples = (item["response"] as? [[String: Any]] ?? []).compactMap { source -> ResponseExample? in
                    let body = source["body"] as? String ?? ""
                    guard body.utf8.count <= ResponseExample.maximumBodyBytes else { return nil }
                    return ResponseExample(name: source["name"] as? String ?? "Example", status: source["code"] as? Int ?? 200, headers: fields(source["header"] as? [[String: Any]] ?? []), body: body)
                }.prefix(ResponseExample.maximumCount)
                if !examples.isEmpty { request.examples = Array(examples) }
                requests.append(request)
            }
        }
        try walk(root["item"] as? [[String: Any]] ?? [], path: "", inheritedAuth: root["auth"] as? [String: Any], inheritedEvents: [], parent: nil)
        let name = (root["info"] as? [String: Any])?["name"] as? String ?? "Postman collection"
        let variables = fields(root["variable"] as? [[String: Any]] ?? [])
        if requests.contains(where: { !$0.preScript.isEmpty || !$0.postScript.isEmpty }) || !(root["event"] as? [Any] ?? []).isEmpty || folders.contains(where: { !$0.defaults.preScript.isEmpty || !$0.defaults.postScript.isEmpty }) { warnings.append(String(localized: "Imported scripts run when you send. Review them in each Scripts tab; turn off Run scripts to skip them.", bundle: .module)) }
        var collection = RequestCollection(name: name, requests: requests)
        collection.folders = folders; collection.defaults = decodeDefaults(root, warnings: &warnings, inherit: false)
        if let text = description((root["info"] as? [String: Any])?["description"]) { collection.defaults?.description = text }
        return CollectionImport(workspace: Workspace(collections: [collection], environments: variables.isEmpty ? [] : [APIEnvironment(name: name, variables: variables)]), warnings: warnings)
    }

    static func decodeAuth(_ source: [String: Any]?, postman: Bool, warnings: inout [String]) -> RequestAuth {
        var auth = RequestAuth()
        guard let source, let type = source["type"] as? String else { return auth }
        if source["disabled"] as? Bool == true { return auth }
        var values = source
        if postman { values = (source[type] as? [[String: Any]] ?? []).reduce(into: [:]) { $0[$1["key"] as? String ?? ""] = $1["value"] } }
        switch type {
        case "bearer": auth.kind = .bearer; auth.token = string(values["token"])
        case "basic": auth.kind = .basic; auth.username = string(values["username"]); auth.password = string(values["password"])
        case "digest": auth.kind = .digest; auth.username = string(values["username"]); auth.password = string(values["password"])
        case "apikey": auth.kind = .apiKey; var key = APIKeyAuth(); key.name = string(values["key"]); key.value = string(values["value"]); key.inQuery = ["query", "queryParams", "queryparams"].contains(string(values["in"] ?? values["addTo"] ?? values["placement"])); auth.apiKey = key
        case "oauth2": auth.kind = .oauth2; var oauth = OAuthConfiguration(); oauth.accessToken = string(values["accessToken"]); oauth.clientID = string(values["clientId"]); oauth.clientSecret = string(values["clientSecret"]); oauth.authorizationURL = string(values["authUrl"] ?? values["authorizationUrl"]); oauth.tokenURL = string(values["accessTokenUrl"] ?? values["tokenUrl"]); oauth.scope = string(values["scope"]); oauth.grant = ["client_credentials": .clientCredentials, "password_credentials": .password, "password": .password][string(values["grant_type"] ?? values["grantType"])] ?? .pkce; if oauth.grant == .password { oauth.username = string(values["username"]); oauth.password = string(values["password"]) }; auth.oauth = oauth
        case "awsv4", "iam", "aws":
            auth.kind = .aws; var aws = AWSAuth(); aws.accessKey = string(values["accessKey"] ?? values["accessKeyId"]); aws.secretKey = string(values["secretKey"] ?? values["secretAccessKey"]); aws.sessionToken = string(values["sessionToken"])
            if values["region"] != nil { aws.region = string(values["region"]) }; if values["service"] != nil { aws.service = string(values["service"]) }; auth.aws = aws
        case "oauth1":
            auth.kind = .oauth1; var oauth1 = OAuth1Auth(); oauth1.consumerKey = string(values["consumerKey"]); oauth1.consumerSecret = string(values["consumerSecret"])
            oauth1.token = string(values["token"] ?? values["tokenKey"] ?? values["accessToken"]); oauth1.tokenSecret = string(values["tokenSecret"] ?? values["accessTokenSecret"]); oauth1.realm = string(values["realm"])
            let method = string(values["signatureMethod"])
            if let signature = OAuth1Signature(rawValue: method.isEmpty ? "HMAC-SHA1" : method.uppercased()) { oauth1.signatureMethod = signature } else { warnings.append(String(localized: "OAuth 1.0 signature method ‘\(method)’ is unsupported; HMAC-SHA1 is used instead.", bundle: .module)) }
            auth.oauth1 = oauth1
        case "jwt":
            auth.kind = .jwt; var jwt = JWTAuth(); let algorithm = string(values["algorithm"]).uppercased()
            if let value = JWTAlgorithm(rawValue: algorithm.isEmpty ? "HS256" : algorithm) { jwt.algorithm = value } else { warnings.append(String(localized: "JWT algorithm ‘\(algorithm)’ is unsupported; HS256 is used instead.", bundle: .module)) }
            jwt.secret = string(values["secret"]); jwt.secretIsBase64 = string(values["isSecretBase64Encoded"]) == "true"; jwt.privateKey = string(values["privateKey"])
            jwt.payload = values["payload"] == nil ? "{}" : string(values["payload"]); jwt.header = values["header"] == nil ? "{}" : string(values["header"])
            jwt.inQuery = string(values["addTokenTo"]) == "queryParam"; jwt.headerPrefix = values["headerPrefix"] == nil ? "Bearer" : string(values["headerPrefix"])
            jwt.queryKey = string(values["queryParamKey"]).isEmpty ? "token" : string(values["queryParamKey"]); auth.jwt = jwt
        case "noauth", "none", "": break
        default: warnings.append(String(localized: "Authentication type ‘\(type)’ is unsupported. Configure an Authorization header manually.", bundle: .module))
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
        var url: [String: Any] = ["raw": raw, "query": query.map(postmanField)]
        if let variables = request.pathVariables, !variables.isEmpty { url["variable"] = variables.map(postmanField) }
        source["url"] = url
        switch request.bodyKind {
        case .none: break
        case .json, .text:
            let type = request.headers.first { $0.enabled && $0.name.lowercased() == "content-type" }?.value.lowercased() ?? ""
            let language = request.bodyKind == .json ? "json" : ["xml", "html", "javascript"].first { type.contains($0) } ?? "text"
            source["body"] = ["mode": "raw", "raw": request.body, "options": ["raw": ["language": language]]]
        case .form: source["body"] = ["mode": "urlencoded", "urlencoded": request.form.map(postmanField)]
        case .multipart: source["body"] = ["mode": "formdata", "formdata": (request.multipart ?? []).map { part in
            var field: [String: Any] = ["key": part.name, "value": part.value, "disabled": !part.enabled, "type": part.file == nil ? "text" : "file"]
            if let file = part.file { field["src"] = file.filename; field["contentType"] = file.mimeType }
            return field
        }]
        case .file: source["body"] = ["mode": "file", "file": ["src": request.fileBody?.filename ?? ""]]
        }
        switch request.auth.kind {
        case .inherit: break
        case .apiKey: source["auth"] = ["type": "apikey", "apikey": [["key": "key", "value": request.auth.apiKey?.name ?? ""], ["key": "value", "value": request.auth.apiKey?.value ?? ""], ["key": "in", "value": request.auth.apiKey?.inQuery == true ? "query" : "header"]]]
        case .oauth2:
            let oauth = request.auth.oauth ?? OAuthConfiguration(), grant = [OAuthGrant.clientCredentials: "client_credentials", .password: "password_credentials"][oauth.grant] ?? "authorization_code_with_pkce"
            source["auth"] = ["type": "oauth2", "oauth2": [["key": "accessToken", "value": oauth.accessToken], ["key": "grant_type", "value": grant], ["key": "accessTokenUrl", "value": oauth.tokenURL], ["key": "authUrl", "value": oauth.authorizationURL],
                                                       ["key": "clientId", "value": oauth.clientID], ["key": "scope", "value": oauth.scope], ["key": "username", "value": oauth.username ?? ""]].filter { !($0["value"] ?? "").isEmpty }]
        case .aws: source["auth"] = ["type": "awsv4", "awsv4": [["key": "accessKey", "value": request.auth.aws?.accessKey ?? ""], ["key": "secretKey", "value": request.auth.aws?.secretKey ?? ""], ["key": "region", "value": request.auth.aws?.region ?? ""], ["key": "service", "value": request.auth.aws?.service ?? ""], ["key": "sessionToken", "value": request.auth.aws?.sessionToken ?? ""]]]
        case .oauth1:
            let oauth1 = request.auth.oauth1 ?? OAuth1Auth()
            source["auth"] = ["type": "oauth1", "oauth1": [["key": "consumerKey", "value": oauth1.consumerKey], ["key": "consumerSecret", "value": oauth1.consumerSecret], ["key": "token", "value": oauth1.token], ["key": "tokenSecret", "value": oauth1.tokenSecret],
                                                       ["key": "signatureMethod", "value": oauth1.signatureMethod.rawValue], ["key": "realm", "value": oauth1.realm], ["key": "version", "value": "1.0"], ["key": "addParamsToHeader", "value": true]]]
        case .jwt:
            let jwt = request.auth.jwt ?? JWTAuth()
            source["auth"] = ["type": "jwt", "jwt": [["key": "algorithm", "value": jwt.algorithm.rawValue], ["key": "isSecretBase64Encoded", "value": jwt.secretIsBase64], ["key": "secret", "value": jwt.secret],
                                                 ["key": "privateKey", "value": jwt.privateKey], ["key": "payload", "value": jwt.payload], ["key": "header", "value": jwt.header], ["key": "addTokenTo", "value": jwt.inQuery ? "queryParam" : "header"],
                                                 ["key": "headerPrefix", "value": jwt.headerPrefix], ["key": "queryParamKey", "value": jwt.queryKey]] as [[String: Any]]]
        case .none: source["auth"] = ["type": "noauth"]
        case .bearer: source["auth"] = ["type": "bearer", "bearer": [["key": "token", "value": request.auth.token, "type": "string"]]]
        case .basic: source["auth"] = ["type": "basic", "basic": [["key": "username", "value": request.auth.username, "type": "string"], ["key": "password", "value": request.auth.password, "type": "string"]]]
        case .digest: source["auth"] = ["type": "digest", "digest": [["key": "username", "value": request.auth.username, "type": "string"], ["key": "password", "value": request.auth.password, "type": "string"]]]
        }
        if request.transport == .graphql { let graph = request.graphql ?? GraphQLRequest(); source["body"] = ["mode": "graphql", "graphql": ["query": graph.query, "variables": graph.variables]] }
        if let text = request.description, !text.isEmpty { source["description"] = text }
        var item: [String: Any] = ["name": request.name, "request": source, "_monkeytail": transportMetadata(request)]
        if let examples = request.examples, !examples.isEmpty {
            item["response"] = examples.map { example -> [String: Any] in
                let type = example.headers.first { $0.name.lowercased() == "content-type" }?.value.lowercased() ?? ""
                return ["name": example.name, "originalRequest": source, "code": example.status, "header": example.headers.map(postmanField), "body": example.body,
                        "_postman_previewlanguage": ["json", "html", "xml"].first { type.contains($0) } ?? "text"]
            }
        }
        item["event"] = [("prerequest", request.preScript), ("test", request.postScript)].filter { !$0.1.isEmpty }.map { ["listen": $0.0, "script": ["type": "text/javascript", "exec": $0.1.components(separatedBy: "\n")]] as [String: Any] }
        return item
    }
    private static func decodeDefaults(_ source: [String: Any], warnings: inout [String], inherit: Bool) -> RequestDefaults {
        if let raw = source["_monkeytailDefaults"], let data = try? json(raw), var value = try? JSONDecoder().decode(RequestDefaults.self, from: data) { return value }
        var value = RequestDefaults(); value.variables = fields(source["variable"] as? [[String: Any]] ?? [])
        value.description = description(source["description"])
        value.auth = decodeAuth(source["auth"] as? [String: Any], postman: true, warnings: &warnings)
        if source["auth"] == nil && inherit { value.auth.kind = .inherit }
        for event in source["event"] as? [[String: Any]] ?? [] {
            let script = event["script"] as? [String: Any], code = (script?["exec"] as? [String])?.joined(separator: "\n") ?? script?["exec"] as? String ?? ""
            if event["listen"] as? String == "prerequest" { value.preScript += code + "\n" }
            if event["listen"] as? String == "test" { value.postScript += code + "\n" }
        }
        return value
    }
    static func decodeAdvanced(_ raw: Any?, into request: inout APIRequest) {
        guard let raw = raw as? [String: Any], let original = try? JSONEncoder().encode(request), var object = try? JSONSerialization.jsonObject(with: original) as? [String: Any] else { return }
        for key in ["transport", "graphql", "assertions", "requestSchema", "responseSchema", "parameterHints", "variables", "cookieJarEnabled", "mock", "auth"] { if let value = raw[key] { object[key] = value } }
        if let data = try? json(object), let decoded = try? JSONDecoder().decode(APIRequest.self, from: data) { request = decoded }
    }
    private static func postmanCollection(_ collection: RequestCollection) -> [String: Any] {
        func children(_ parent: UUID?, seen: Set<UUID>) -> [[String: Any]] {
            guard seen.count < 32 else { return [] }
            let requests = collection.requests.filter { $0.folderID == parent }.map(postmanItem)
            let groups = (collection.folders ?? []).filter { $0.parentID == parent && !seen.contains($0.id) }.map { folder -> [String: Any] in
                var result = defaultsItem(folder.defaults, name: folder.name)
                result["item"] = children(folder.id, seen: seen.union([folder.id])); return result
            }
            return groups + requests
        }
        var result = defaultsItem(collection.defaults ?? RequestDefaults(), name: collection.name)
        result["item"] = children(nil, seen: [])
        // Never silently omit requests whose folders are missing or cyclic.
        let reachable = Set((collection.folders ?? []).filter { folder in
            var current: UUID? = folder.id, visited = Set<UUID>()
            while let id = current { guard visited.count < 32, visited.insert(id).inserted, let item = collection.folders?.first(where: { $0.id == id }) else { return false }; current = item.parentID }; return true
        }.map(\.id))
        result["item"] = (result["item"] as? [[String: Any]] ?? []) + collection.requests.filter { $0.folderID.map { !reachable.contains($0) } ?? false }.map(postmanItem)
        return result
    }
    private static func defaultsItem(_ defaults: RequestDefaults, name: String) -> [String: Any] {
        var request = APIRequest(); request.auth = defaults.auth; request.preScript = defaults.preScript; request.postScript = defaults.postScript
        let item = postmanItem(request), source = item["request"] as? [String: Any] ?? [:]
        var result: [String: Any] = ["name": name, "variable": defaults.variables.map(postmanField), "event": item["event"] ?? []]
        result["auth"] = source["auth"]
        if let text = defaults.description, !text.isEmpty { result["description"] = text }
        if let data = try? JSONEncoder().encode(defaults), let encoded = try? JSONSerialization.jsonObject(with: data) { result["_monkeytailDefaults"] = encoded }
        return result
    }
    /// Postman stores descriptions as a string or `{content, type}`.
    static func description(_ value: Any?) -> String? {
        let text = value as? String ?? (value as? [String: Any])?["content"] as? String
        return text?.isEmpty == false ? text : nil
    }
    static func fields(_ source: [[String: Any]]) -> [Field] {
        source.map { Field(normalizeInsomnia($0["key"] as? String ?? $0["name"] as? String ?? ""), normalizeInsomnia(string($0["value"])), enabled: !($0["disabled"] as? Bool ?? false) && ($0["enabled"] as? Bool ?? true)) }
    }
    private static func transportMetadata(_ request: APIRequest) -> [String: Any] {
        var metadata: [String: Any] = [:]
        if let value = request.impersonation { metadata["tlsProfile"] = value.profile.rawValue; metadata["browserHeaders"] = value.browserHeaders }
        if let encoded = try? JSONEncoder().encode(request), let object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            for key in ["transport", "graphql", "assertions", "requestSchema", "responseSchema", "parameterHints", "variables", "cookieJarEnabled", "mock", "auth"] { metadata[key] = object[key] }
        }
        return metadata
    }
    static func decodeTransport(_ value: Any?) throws -> BrowserImpersonation? {
        guard let metadata = value as? [String: Any], let name = metadata["tlsProfile"] as? String else { return nil }
        return BrowserImpersonation(profile: try BrowserProfile.parse(name), browserHeaders: metadata["browserHeaders"] as? Bool ?? true)
    }
    static func string(_ value: Any?) -> String {
        guard let value else { return "" }
        if let value = value as? String { return value }
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) { return String(decoding: data, as: UTF8.self) }
        return String(describing: value)
    }
    static func normalizeInsomnia(_ value: String) -> String {
        value.replacingOccurrences(of: #"\{\{\s*_\.([\w.\-]+)\s*\}\}"#, with: "{{$1}}", options: .regularExpression)
            .replacingOccurrences(of: #"\{\{\s*_\[\s*['"]([^'"\]]+)['"]\s*\]\s*\}\}"#, with: "{{$1}}", options: .regularExpression)
            .replacingOccurrences(of: #"\{\{\s+([\w.\-$]+)\s*\}\}|\{\{([\w.\-$]+)\s+\}\}"#, with: "{{$1$2}}", options: .regularExpression)
    }
    static func withoutQuery(_ value: String) -> String {
        let withoutFragment = String(value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        return String(withoutFragment.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }
    private static func postmanField(_ field: Field) -> [String: Any] { ["key": field.name, "value": field.value, "disabled": !field.enabled, "type": "text"] }
    private static func insomniaField(_ field: Field) -> [String: Any] { ["name": field.name, "value": field.value, "disabled": !field.enabled] }
    static func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) }
}

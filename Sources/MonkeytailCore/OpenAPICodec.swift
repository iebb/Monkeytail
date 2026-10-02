import Foundation
import Yams

public enum OpenAPICodec {
    public static func decode(_ data: Data) throws -> CollectionImport {
        guard data.count <= 10 * 1024 * 1024 else { throw ClientError("OpenAPI specifications must be smaller than 10 MB.") }
        let root: [String: Any]
        if let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { root = value }
        else {
            guard let node = try Yams.compose(yaml: String(decoding: data, as: UTF8.self)) else { throw ClientError("Empty specification.") }
            var count = 0
            func convert(_ node: Node, depth: Int) throws -> Any {
                count += 1
                guard count < 50000, depth < 64 else { throw ClientError("YAML specification exceeds the depth or node limit.") }
                switch node {
                case .scalar: return node.any
                case .sequence(let values): return try values.map { try convert($0, depth: depth + 1) }
                case .mapping(let pairs):
                    var result: [String: Any] = [:]
                    for pair in pairs {
                        guard let key = pair.key.string, result[key] == nil else { throw ClientError("YAML contains duplicate or non-string keys.") }
                        result[key] = try convert(pair.value, depth: depth + 1)
                    }
                    return result
                case .alias: throw ClientError("YAML aliases must be expanded before importing.")
                }
            }
            guard let value = try convert(node, depth: 0) as? [String: Any] else { throw ClientError("Expected an OpenAPI document.") }; root = value
        }
        guard (root["openapi"] as? String)?.hasPrefix("3.") == true || root["swagger"] as? String == "2.0" else { throw ClientError("Import an OpenAPI 3.x or Swagger 2.0 JSON/YAML specification.") }
        func object(_ raw: Any?, depth: Int = 0) throws -> [String: Any] {
            guard depth < 32 else { throw ClientError("Specification reference cycle.") }
            guard let value = raw as? [String: Any] else { return [:] }
            if let ref = value["$ref"] as? String {
                guard ref.hasPrefix("#/") else { throw ClientError("External specification references must be bundled before import: \(ref)") }
                var cursor: Any = root
                for item in ref.dropFirst(2).components(separatedBy: "/") {
                    let key = item.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                    guard let next = (cursor as? [String: Any])?[key] else { throw ClientError("Missing specification reference: \(ref)") }; cursor = next
                }
                return try object(cursor, depth: depth + 1)
            }
            return value
        }
        func text(_ value: Any?) -> String {
            if let value = value as? String { return value }
            if let value, let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) { return String(decoding: data, as: UTF8.self) }
            return ""
        }
        func schemaText(_ raw: Any?) throws -> String? {
            guard var schema = raw as? [String: Any] else { return nil }
            if let components = root["components"] { schema["components"] = components }
            if let definitions = root["definitions"] { schema["definitions"] = definitions }
            return String(decoding: try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]), as: UTF8.self)
        }
        func exampleValue(_ raw: Any?, depth: Int = 0) throws -> Any {
            guard depth < 12 else { return NSNull() }
            let schema = try object(raw)
            if let value = schema["example"] ?? schema["default"] ?? schema["const"] ?? (schema["enum"] as? [Any])?.first { return value }
            if let choice = (schema["oneOf"] as? [Any])?.first ?? (schema["anyOf"] as? [Any])?.first { return try exampleValue(choice, depth: depth + 1) }
            switch schema["type"] as? String ?? (schema["properties"] != nil ? "object" : "string") {
            case "object":
                var result: [String: Any] = [:]
                for (name, field) in (schema["properties"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }).prefix(100) { result[name] = try exampleValue(field, depth: depth + 1) }
                return result
            case "array": return [try exampleValue(schema["items"], depth: depth + 1)]
            case "integer", "number": return schema["minimum"] ?? 1
            case "boolean": return true
            case "null": return NSNull()
            default: return "string"
            }
        }
        var server = (root["servers"] as? [[String: Any]])?.first?["url"] as? String ?? ""
        if server.isEmpty, let host = root["host"] as? String { server = ((root["schemes"] as? [String])?.first ?? "https") + "://" + host + (root["basePath"] as? String ?? "") }
        if server.isEmpty { server = "https://api.example.com" }
        if let serverObject = (root["servers"] as? [[String: Any]])?.first, let variables = serverObject["variables"] as? [String: [String: Any]] {
            for (key, value) in variables { server = server.replacingOccurrences(of: "{\(key)}", with: text(value["default"])) }
        }
        let title = (root["info"] as? [String: Any])?["title"] as? String ?? "Imported API"
        var collection = RequestCollection(name: title), folders: [String: UUID] = [:], warnings: [String] = []
        let securitySchemes = (root["components"] as? [String: Any])?["securitySchemes"] as? [String: Any] ?? root["securityDefinitions"] as? [String: Any] ?? [:]
        for (path, raw) in (root["paths"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let pathObject = try object(raw)
            for method in ["get", "post", "put", "patch", "delete", "head", "options", "trace"] {
                guard let operationRaw = pathObject[method] else { continue }
                let operation = try object(operationRaw)
                var urlPath = path
                let name = operation["summary"] as? String ?? operation["operationId"] as? String ?? method.uppercased() + " " + path
                var request = APIRequest(name: name, method: method.uppercased(), url: "")
                request.variables = []; request.parameterHints = []; request.headers = []
                let parameters = try ((pathObject["parameters"] as? [Any] ?? []) + (operation["parameters"] as? [Any] ?? [])).map { try object($0) }
                // Operation-level parameters override a path parameter of the same name/location.
                var merged: [String: [String: Any]] = [:]
                for parameter in parameters { merged[text(parameter["in"]) + "." + text(parameter["name"])] = parameter }
                for parameter in merged.values.sorted(by: { text($0["name"]) < text($1["name"]) }) {
                    let name = text(parameter["name"]), location = text(parameter["in"]), schema = try object(parameter["schema"] ?? parameter)
                    let sample = parameter["example"] ?? schema["example"] ?? schema["default"] ?? (schema["enum"] as? [Any])?.first
                    let value = text(sample).isEmpty ? (schema["type"] as? String == "integer" ? "1" : "") : text(sample)
                    request.parameterHints?.append(ParameterHint(name: name, location: location, description: text(parameter["description"]), type: text(schema["type"]), required: parameter["required"] as? Bool ?? false))
                    switch location {
                    case "path": urlPath = urlPath.replacingOccurrences(of: "{\(name)}", with: "{{\(name)}}"); request.variables?.append(Field(name, value))
                    case "query": request.query.append(Field(name, value, enabled: parameter["required"] as? Bool ?? false || sample != nil))
                    case "header": request.headers.append(Field(name, value, enabled: parameter["required"] as? Bool ?? false || sample != nil))
                    case "body": request.bodyKind = .json; request.body = text(try exampleValue(parameter["schema"])); request.requestSchema = try schemaText(parameter["schema"])
                    case "formData": request.bodyKind = .form; request.form.append(Field(name, value))
                    default: warnings.append("Parameter location \(location) requires manual setup.")
                    }
                }
                request.url = "{{base_url}}" + urlPath
                if let body = operation["requestBody"] {
                    let content = try object(body)["content"] as? [String: [String: Any]] ?? [:]
                    if let mime = content.keys.sorted().first(where: { $0.contains("json") }) {
                        let entry = content[mime]!, schema = try object(entry["schema"])
                        let examples = entry["examples"] as? [String: [String: Any]] ?? [:]
                        let example = try entry["example"] ?? examples.keys.sorted().first.flatMap { examples[$0]?["value"] } ?? schema["example"] ?? exampleValue(entry["schema"])
                        request.bodyKind = .json; request.body = text(example); request.headers.append(Field("Content-Type", mime)); request.requestSchema = try schemaText(entry["schema"])
                    } else if let mime = content.keys.sorted().first {
                        request.bodyKind = mime.contains("multipart") ? .multipart : mime.contains("x-www-form-urlencoded") ? .form : .text
                        request.headers.append(Field("Content-Type", mime))
                        warnings.append("\(name): configure \(mime) body fields before sending.")
                    }
                }
                if let responses = operation["responses"] as? [String: Any], let responseKey = responses.keys.sorted().first(where: { $0.hasPrefix("2") }) {
                    let response = try object(responses[responseKey]), content = response["content"] as? [String: [String: Any]] ?? [:]
                    request.responseSchema = try schemaText(content.keys.sorted().first(where: { $0.contains("json") }).flatMap { content[$0]?["schema"] } ?? response["schema"])
                }
                if let selected = ((operation["security"] ?? root["security"]) as? [[String: Any]])?.first?.keys.sorted().first {
                    let security = try object(securitySchemes[selected])
                    switch security["type"] as? String {
                    case "apiKey": var key = APIKeyAuth(); key.name = text(security["name"]); key.inQuery = security["in"] as? String == "query"; request.auth.kind = .apiKey; request.auth.apiKey = key
                    case "http": request.auth.kind = security["scheme"] as? String == "basic" ? .basic : .bearer
                    case "basic": request.auth.kind = .basic
                    case "oauth2":
                        request.auth.kind = .oauth2; var config = OAuthConfiguration()
                        let flows = security["flows"] as? [String: [String: Any]] ?? [:], flow = flows["authorizationCode"] ?? flows["clientCredentials"] ?? security
                        config.grant = flows["clientCredentials"] != nil && flows["authorizationCode"] == nil ? .clientCredentials : .pkce
                        config.authorizationURL = text(flow["authorizationUrl"]); config.tokenURL = text(flow["tokenUrl"]); request.auth.oauth = config
                    default: warnings.append("\(name): configure authentication manually.")
                    }
                }
                if let tag = (operation["tags"] as? [String])?.first {
                    if folders[tag] == nil { let folder = RequestFolder(name: tag); collection.folders = (collection.folders ?? []) + [folder]; folders[tag] = folder.id }
                    request.folderID = folders[tag]
                }
                collection.requests.append(request)
                guard collection.requests.count <= 2000 else { throw ClientError("Specification exceeds 2,000 operations.") }
            }
        }
        guard !collection.requests.isEmpty else { throw ClientError("The specification contains no HTTP operations.") }
        var workspace = Workspace(collections: [collection], environments: [APIEnvironment(name: title, variables: [Field("base_url", server.trimmingCharacters(in: CharacterSet(charactersIn: "/")))])])
        workspace.selectedEnvironmentID = workspace.environments.first?.id
        return CollectionImport(workspace: workspace, warnings: Array(Set(warnings)).sorted())
    }
}

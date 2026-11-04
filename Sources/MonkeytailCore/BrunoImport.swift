import Foundation

/// Bruno collections: folders of `.bru` files and the JSON collection export.
enum BrunoImport {
    private static let methods: Set = ["get", "post", "put", "patch", "delete", "options", "head", "connect", "trace"]

    static func looksLikeBru(_ text: String) -> Bool {
        text.range(of: #"(?m)^(meta|get|post|put|patch|delete|options|head|http|vars)\s*\{\s*$"#, options: .regularExpression) != nil && text.range(of: #"(?m)^\}\s*$"#, options: .regularExpression) != nil
    }

    static func decodeJSON(_ root: [String: Any]) throws -> CollectionImport {
        var warnings: [String] = []
        var collection = RequestCollection(name: root["name"] as? String ?? "Bruno collection"), folders: [RequestFolder] = []
        try walk(root["items"] as? [[String: Any]] ?? [], parent: nil, depth: 0, collection: &collection, folders: &folders, warnings: &warnings)
        collection.folders = folders.isEmpty ? nil : folders
        collection.defaults = defaults(root["root"] as? [String: Any], inherit: false, warnings: &warnings)
        let environments = (root["environments"] as? [[String: Any]] ?? []).map { APIEnvironment(name: $0["name"] as? String ?? "Environment", variables: variables($0["variables"])) }
        return finish(Workspace(collections: [collection], environments: environments), warnings: warnings)
    }

    /// Decodes `.bru` files. Paths are relative to the collection folder; `bruno.json` supplies its name.
    static func decode(files: [ImportFile], name: String) throws -> CollectionImport {
        guard files.count <= 5000 else { throw ClientError("Bruno collections can contain at most 5,000 files.") }
        var warnings: [String] = [], environments: [APIEnvironment] = []
        var collectionName = name, rootDefaults: [String: Any]?
        var folderItems: [String: [String: Any]] = [:], requests: [(path: String, item: [String: Any])] = []
        for file in files {
            let components = file.path.split(separator: "/").map(String.init), filename = components.last ?? file.path
            if filename == "bruno.json" {
                if let object = try? JSONSerialization.jsonObject(with: Data(file.text.utf8)) as? [String: Any], let value = object["name"] as? String, !value.isEmpty { collectionName = value }
                continue
            }
            let blocks = parse(file.text)
            if components.dropLast().last == "environments" || (blocks.contains { $0.name == "vars" || $0.name == "vars:secret" } && !blocks.contains { methods.contains($0.name) || $0.name == "http" || $0.name == "meta" }) {
                let secrets = Set(blocks.first { $0.name == "vars:secret" }?.lines.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ,")) } ?? [])
                var fields = pairs(blocks.first { $0.name == "vars" }?.lines ?? []).map { Field($0.name, $0.value, enabled: $0.enabled) }
                fields += secrets.filter { !$0.isEmpty && !fields.map(\.name).contains($0) }.sorted().map { Field($0, "") }
                for index in fields.indices where secrets.contains(fields[index].name) { fields[index].secret = true }
                environments.append(APIEnvironment(name: (filename as NSString).deletingPathExtension, variables: fields))
                if !secrets.isEmpty { warnings.append("Bruno secret values are stored outside the collection. Enter them in the imported environments.") }
                continue
            }
            let item = self.item(blocks, fallbackName: (filename as NSString).deletingPathExtension)
            if filename == "collection.bru" { rootDefaults = item; continue }
            if filename == "folder.bru" { folderItems[components.dropLast().joined(separator: "/")] = item; continue }
            requests.append((file.path, item))
        }
        // Rebuild the folder tree from directory paths.
        var nodes: [String: [String: Any]] = ["": ["type": "folder", "items": [[String: Any]]()]]
        func node(_ path: String) {
            guard nodes[path] == nil else { return }
            let parent = (path as NSString).deletingLastPathComponent
            node(parent)
            var folder = folderItems[path] ?? [:]
            folder["type"] = "folder"; folder["items"] = [[String: Any]]()
            if folder["name"] == nil || CollectionCodec.string(folder["name"]).isEmpty { folder["name"] = (path as NSString).lastPathComponent }
            nodes[path] = folder
        }
        for request in requests { node((request.path as NSString).deletingLastPathComponent) }
        for path in folderItems.keys { node(path) }
        for request in requests { let parent = (request.path as NSString).deletingLastPathComponent; nodes[parent]!["items"] = (nodes[parent]!["items"] as! [[String: Any]]) + [request.item] }
        func assemble(_ path: String) -> [String: Any] {
            var folder = nodes[path]!
            let children = nodes.keys.filter { $0 != path && ($0 as NSString).deletingLastPathComponent == path }.sorted()
            folder["items"] = (folder["items"] as! [[String: Any]]) + children.map(assemble)
            return folder
        }
        var collection = RequestCollection(name: collectionName), folders: [RequestFolder] = []
        try walk(assemble("")["items"] as? [[String: Any]] ?? [], parent: nil, depth: 0, collection: &collection, folders: &folders, warnings: &warnings)
        collection.folders = folders.isEmpty ? nil : folders
        collection.defaults = defaults(rootDefaults, inherit: false, warnings: &warnings)
        if let docs = rootDefaults?["docs"] as? String, !docs.isEmpty { collection.defaults?.description = docs }
        return finish(Workspace(collections: [collection], environments: environments.sorted { $0.name < $1.name }), warnings: warnings)
    }

    private static func finish(_ workspace: Workspace, warnings: [String]) -> CollectionImport {
        var warnings = warnings
        let collection = workspace.collections.first
        if collection?.requests.contains(where: { !$0.preScript.isEmpty || !$0.postScript.isEmpty }) == true || collection?.folders?.contains(where: { !$0.defaults.preScript.isEmpty || !$0.defaults.postScript.isEmpty }) == true {
            warnings.append("Imported scripts run when you send. Bruno’s bru, req, res, test and expect are available; assertions were converted to tests.")
        }
        return CollectionImport(workspace: workspace, warnings: InterchangeImport.unique(warnings))
    }

    private static func walk(_ items: [[String: Any]], parent: UUID?, depth: Int, collection: inout RequestCollection, folders: inout [RequestFolder], warnings: inout [String]) throws {
        guard depth < 32, folders.count < 2000 else { throw ClientError("Bruno folders exceed the depth or count limit.") }
        let sorted = items.enumerated().sorted { (($0.element["seq"] as? NSNumber)?.doubleValue ?? Double($0.offset)) < (($1.element["seq"] as? NSNumber)?.doubleValue ?? Double($1.offset)) }.map(\.element)
        var skipped = 0
        for item in sorted {
            switch item["type"] as? String {
            case "folder":
                var folder = RequestFolder(name: item["name"] as? String ?? "Folder", parentID: parent)
                let root = item["root"] as? [String: Any] ?? item
                folder.defaults = defaults(root, inherit: true, warnings: &warnings)
                if let docs = (root["docs"] ?? item["docs"]) as? String, !docs.isEmpty { folder.defaults.description = docs }
                folders.append(folder)
                try walk(item["items"] as? [[String: Any]] ?? [], parent: folder.id, depth: depth + 1, collection: &collection, folders: &folders, warnings: &warnings)
            case "http-request", "graphql-request":
                var request = self.request(item, warnings: &warnings); request.folderID = parent
                collection.requests.append(request)
            case "ws-request":
                let source = item["request"] as? [String: Any] ?? [:]
                var request = APIRequest(name: item["name"] as? String ?? "WebSocket", url: CollectionCodec.string(source["url"])); request.transport = .websocket; request.folderID = parent
                request.headers = CollectionCodec.fields(source["headers"] as? [[String: Any]] ?? [])
                collection.requests.append(request)
            default: skipped += 1
            }
        }
        if skipped > 0 { warnings.append("Skipped \(skipped) gRPC or script \(skipped == 1 ? "item" : "items"). Monkeytail imports HTTP, GraphQL and WebSocket requests.") }
    }

    private static func request(_ item: [String: Any], warnings: inout [String]) -> APIRequest {
        let source = item["request"] as? [String: Any] ?? [:]
        let url = CollectionCodec.string(source["url"])
        var request = APIRequest(name: item["name"] as? String ?? "Untitled", method: CollectionCodec.string(source["method"]).isEmpty ? "GET" : CollectionCodec.string(source["method"]).uppercased(), url: url)
        let params = source["params"] as? [[String: Any]] ?? []
        let query = params.filter { $0["type"] as? String != "path" }, path = params.filter { $0["type"] as? String == "path" }
        if !query.isEmpty { request.query = CollectionCodec.fields(query); request.url = CollectionCodec.withoutQuery(url) }
        if !path.isEmpty { request.pathVariables = CollectionCodec.fields(path) }
        request.headers = CollectionCodec.fields(source["headers"] as? [[String: Any]] ?? [])
        let body = source["body"] as? [String: Any] ?? [:]
        let contentType = { (type: String) in if !request.headers.contains(where: { $0.name.lowercased() == "content-type" }) { request.headers.append(Field("Content-Type", type)) } }
        switch body["mode"] as? String {
        case "json": request.bodyKind = .json; request.body = CollectionCodec.string(body["json"]); contentType("application/json")
        case "text": request.bodyKind = .text; request.body = CollectionCodec.string(body["text"]); contentType("text/plain")
        case "xml": request.bodyKind = .text; request.body = CollectionCodec.string(body["xml"]); contentType("application/xml")
        case "sparql": request.bodyKind = .text; request.body = CollectionCodec.string(body["sparql"]); contentType("application/sparql-query")
        case "formUrlEncoded": request.bodyKind = .form; request.form = CollectionCodec.fields(body["formUrlEncoded"] as? [[String: Any]] ?? [])
        case "multipartForm":
            request.bodyKind = .multipart
            request.multipart = (body["multipartForm"] as? [[String: Any]] ?? []).flatMap { part -> [MultipartPart] in
                let name = CollectionCodec.string(part["name"]), enabled = part["enabled"] as? Bool ?? true
                guard part["type"] as? String == "file" else { return [MultipartPart(name: name, value: CollectionCodec.string(part["value"]), enabled: enabled)] }
                let paths = part["value"] as? [String] ?? [CollectionCodec.string(part["value"])]
                return paths.map { MultipartPart(name: name, enabled: enabled, file: RequestFile(filename: ($0 as NSString).lastPathComponent, mimeType: (part["contentType"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream")) }
            }
            if request.multipart?.contains(where: { $0.file != nil }) == true { warnings.append("Choose imported attachment files on this device before sending.") }
        case "file":
            let files = body["file"] as? [[String: Any]] ?? [], chosen = files.first { $0["selected"] as? Bool ?? true } ?? files.first
            request.bodyKind = .file; request.fileBody = RequestFile(filename: (CollectionCodec.string(chosen?["filePath"]) as NSString).lastPathComponent, mimeType: (chosen?["contentType"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream")
            warnings.append("Choose the imported body file on this device before sending.")
        case "graphql":
            let graph = body["graphql"] as? [String: Any] ?? [:]
            var graphql = GraphQLRequest(); graphql.query = CollectionCodec.string(graph["query"]); graphql.variables = CollectionCodec.string(graph["variables"]).isEmpty ? "{}" : CollectionCodec.string(graph["variables"])
            request.transport = .graphql; request.graphql = graphql; request.bodyKind = .json
            request.body = String(decoding: (try? CollectionCodec.json(["query": graphql.query])) ?? Data(), as: UTF8.self); contentType("application/json")
        default: break
        }
        request.auth = auth(source["auth"], warnings: &warnings)
        let script = source["script"] as? [String: Any], vars = source["vars"] as? [String: Any]
        request.preScript = CollectionCodec.string(script?["req"])
        request.postScript = postScript(script: script, vars: vars, assertions: source["assertions"], tests: source["tests"])
        let requestVariables = CollectionCodec.fields(vars?["req"] as? [[String: Any]] ?? []); if !requestVariables.isEmpty { request.variables = requestVariables }
        request.description = CollectionCodec.description(source["docs"] ?? item["description"])
        if let settings = item["settings"] as? [String: Any] {
            if let follow = settings["followRedirects"] as? Bool { request.followRedirects = follow }
            if let timeout = (settings["timeout"] as? NSNumber)?.doubleValue, timeout > 0 { request.timeout = min(timeout / 1000, 600) }
        }
        let examples = (item["examples"] as? [[String: Any]] ?? []).prefix(ResponseExample.maximumCount).compactMap { example -> ResponseExample? in
            let response = example["response"] as? [String: Any] ?? [:], content = (response["body"] as? [String: Any])?["content"]
            let text = content as? String ?? content.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
            guard text.utf8.count <= ResponseExample.maximumBodyBytes else { return nil }
            return ResponseExample(name: example["name"] as? String ?? "Example", status: (response["status"] as? NSNumber)?.intValue ?? 200, headers: CollectionCodec.fields(response["headers"] as? [[String: Any]] ?? []), body: text)
        }
        if !examples.isEmpty { request.examples = examples }
        return request
    }

    private static func postScript(script: [String: Any]?, vars: [String: Any]?, assertions: Any?, tests: Any?) -> String {
        func quoted(_ value: String) -> String { String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)) ?? Data("\"\"".utf8), as: UTF8.self) }
        let responseVariables = (vars?["res"] as? [[String: Any]] ?? []).filter { $0["enabled"] as? Bool ?? true }.compactMap { variable -> String? in
            let name = CollectionCodec.string(variable["name"]), value = CollectionCodec.string(variable["value"])
            return name.isEmpty || value.isEmpty ? nil : "try { bru.setVar(\(quoted(name)), \(value)); } catch (e) { console.warn('Could not set \(name): ' + e.message); }"
        }
        let checks = (assertions as? [[String: Any]] ?? []).filter { $0["enabled"] as? Bool ?? true }.compactMap { assertion -> String? in
            let target = CollectionCodec.string(assertion["name"]), raw = CollectionCodec.string(assertion["value"]).trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty else { return nil }
            let parts = raw.split(separator: " ", maxSplits: 1).map(String.init), operation = parts.first ?? "eq", operand = parts.count > 1 ? literal(parts[1]) : literal(raw)
            let unary = ["isEmpty": "to.be.empty", "isNotEmpty": "to.not.be.empty", "isNull": "to.be.null", "isUndefined": "to.be.undefined", "isDefined": "to.exist", "isTruthy": "to.be.ok", "isFalsy": "to.not.be.ok",
                         "isNumber": "to.be.a('number')", "isString": "to.be.a('string')", "isBoolean": "to.be.a('boolean')", "isArray": "to.be.an('array')", "isJson": "to.be.an('object')"]
            let binary = ["eq": "to.eql", "neq": "to.not.eql", "gt": "to.be.above", "gte": "to.be.at.least", "lt": "to.be.below", "lte": "to.be.at.most", "contains": "to.include", "notContains": "to.not.include", "length": "to.have.lengthOf"]
            let check: String
            if let chain = unary[operation] { check = "expect(\(target)).\(chain);" }
            else if let chain = binary[operation] { check = "expect(\(target)).\(chain)(\(operand));" }
            else if ["matches", "notMatches"].contains(operation) { check = "expect(\(operation == "matches" ? "" : "!")new RegExp(\(operand)).test(String(\(target)))).to.equal(true);" }
            else if ["startsWith", "endsWith"].contains(operation) { check = "expect(String(\(target)).\(operation)(\(operand))).to.equal(true);" }
            else if ["in", "notIn"].contains(operation) { check = "expect(\(operation == "in" ? "" : "!")[\(parts.count > 1 ? parts[1] : "")].includes(\(target))).to.equal(true);" }
            else if operation == "between", parts.count > 1 { let bounds = parts[1].split(separator: ",").map { literal($0.trimmingCharacters(in: .whitespaces)) }; check = "expect(\(target)).to.be.within(\(bounds.joined(separator: ", ")));" }
            else { check = "expect(\(target)).to.eql(\(literal(raw)));" }
            return "test(\(quoted("\(target): \(raw)")), function() { \(check) });"
        }
        return [CollectionCodec.string(script?["res"]), responseVariables.joined(separator: "\n"), checks.joined(separator: "\n"), CollectionCodec.string(tests)].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
    }

    /// Bruno assertion operands: numbers, booleans, null, quoted strings or bare text.
    private static func literal(_ value: String) -> String {
        if ["true", "false", "null", "undefined"].contains(value) || Double(value) != nil { return value }
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" || first == "`" { return value }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed)) ?? Data(), as: UTF8.self)
    }

    private static func auth(_ source: Any?, warnings: inout [String]) -> RequestAuth {
        var auth = RequestAuth()
        guard let source = source as? [String: Any], let mode = source["mode"] as? String else { return auth }
        switch mode {
        case "inherit": auth.kind = .inherit
        case "none": break
        case "bearer", "basic", "digest", "apikey", "awsv4", "oauth1", "oauth2":
            var values = source[mode] as? [String: Any] ?? [:]; values["type"] = mode
            auth = CollectionCodec.decodeAuth(values, postman: false, warnings: &warnings)
        default: warnings.append("Bruno authentication ‘\(mode)’ is unsupported. Configure it manually.")
        }
        return auth
    }

    private static func defaults(_ source: [String: Any]?, inherit: Bool, warnings: inout [String]) -> RequestDefaults {
        var defaults = RequestDefaults()
        let request = source?["request"] as? [String: Any] ?? [:]
        defaults.headers = CollectionCodec.fields(request["headers"] as? [[String: Any]] ?? [])
        defaults.variables = CollectionCodec.fields((request["vars"] as? [String: Any])?["req"] as? [[String: Any]] ?? [])
        defaults.auth = request["auth"] == nil && inherit ? { var auth = RequestAuth(); auth.kind = .inherit; return auth }() : auth(request["auth"], warnings: &warnings)
        if defaults.auth.kind == .inherit && !inherit { defaults.auth.kind = .none }
        let script = request["script"] as? [String: Any]
        defaults.preScript = CollectionCodec.string(script?["req"])
        defaults.postScript = postScript(script: script, vars: request["vars"] as? [String: Any], assertions: nil, tests: request["tests"])
        defaults.description = CollectionCodec.description(source?["docs"])
        return defaults
    }

    private static func variables(_ source: Any?) -> [Field] {
        (source as? [[String: Any]] ?? []).map { item in
            var field = Field(CollectionCodec.string(item["name"]), CollectionCodec.string(item["value"]), enabled: item["enabled"] as? Bool ?? true)
            if item["secret"] as? Bool == true { field.secret = true }
            return field
        }
    }

    // MARK: .bru text

    struct Block { var name: String; var lines: [String] }

    /// Splits a `.bru` file into top-level blocks, removing their two-space indent.
    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = [], current: Block?, closing = "}"
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if current == nil {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let last = trimmed.last, last == "{" || last == "[" else { continue }
                let name = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name.range(of: #"^[\w:\-.]+$"#, options: .regularExpression) != nil else { continue }
                current = Block(name: name, lines: []); closing = last == "{" ? "}" : "]"
            } else if line.trimmingCharacters(in: .whitespaces) == closing && !line.hasPrefix(" ") {
                blocks.append(current!); current = nil
            } else {
                current!.lines.append(line.hasPrefix("  ") ? String(line.dropFirst(2)) : line)
            }
        }
        if let current { blocks.append(current) }
        return blocks
    }

    /// Dictionary entries: `name: value`, `~name: value` when disabled, quoted keys and `'''` multiline values.
    static func pairs(_ lines: [String]) -> [(name: String, value: String, enabled: Bool)] {
        var result: [(name: String, value: String, enabled: Bool)] = [], index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces); index += 1
            guard !trimmed.isEmpty, !trimmed.hasPrefix("@") else { continue }
            var rest = Substring(trimmed), enabled = true
            if rest.hasPrefix("~") { enabled = false; rest = rest.dropFirst() }
            var name = ""
            if rest.hasPrefix("\"") {
                rest = rest.dropFirst(); var escaped = false
                while let character = rest.first {
                    rest = rest.dropFirst()
                    if escaped { name.append(character); escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { break } else { name.append(character) }
                }
                guard let colon = rest.firstIndex(of: ":") else { continue }
                rest = rest[rest.index(after: colon)...]
            } else {
                guard let colon = rest.firstIndex(of: ":") else { continue }
                name = rest[..<colon].trimmingCharacters(in: .whitespaces); rest = rest[rest.index(after: colon)...]
            }
            var value = rest.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("'''") {
                if value.count >= 6 && value.hasSuffix("'''") { value = String(value.dropFirst(3).dropLast(3)) }
                else {
                    var collected: [String] = []
                    while index < lines.count {
                        let line = lines[index]; index += 1
                        if line.trimmingCharacters(in: .whitespaces).hasPrefix("'''") { break }
                        collected.append(line.hasPrefix("  ") ? String(line.dropFirst(2)) : line)
                    }
                    value = collected.joined(separator: "\n")
                }
            }
            result.append((name, value, enabled))
        }
        return result
    }

    /// Converts parsed blocks into the shape of a Bruno JSON item.
    private static func item(_ blocks: [Block], fallbackName: String) -> [String: Any] {
        func block(_ name: String) -> Block? { blocks.first { $0.name == name } }
        func dictionary(_ name: String) -> [String: String] { pairs(block(name)?.lines ?? []).filter(\.enabled).reduce(into: [:]) { $0[$1.name] = $1.value } }
        func list(_ name: String, extra: [String: Any] = [:]) -> [[String: Any]] { pairs(block(name)?.lines ?? []).map { ["name": $0.name, "value": $0.value, "enabled": $0.enabled].merging(extra) { first, _ in first } } }
        func text(_ name: String) -> String? { block(name).map { $0.lines.joined(separator: "\n").trimmingCharacters(in: .newlines) } }
        let meta = dictionary("meta")
        var item: [String: Any] = ["name": meta["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName, "type": meta["type"] == "graphql" ? "graphql-request" : "http-request"]
        if let seq = Double(meta["seq"] ?? "") { item["seq"] = seq }
        let http = blocks.first { methods.contains($0.name) || $0.name == "http" }
        let line = http.map { pairs($0.lines).reduce(into: [String: String]()) { $0[$1.name] = $1.value } } ?? [:]
        var request: [String: Any] = ["url": line["url"] ?? "", "method": http?.name == "http" ? (line["method"] ?? "GET") : (http?.name ?? "get")]
        request["headers"] = list("headers")
        request["params"] = list("params:query", extra: ["type": "query"]) + list("query", extra: ["type": "query"]) + list("params:path", extra: ["type": "path"])
        var body: [String: Any] = ["mode": line["body"] ?? "none"]
        if let value = text("body:json") ?? text("body") { body["json"] = value }
        if let value = text("body:text") { body["text"] = value }
        if let value = text("body:xml") { body["xml"] = value }
        if let value = text("body:sparql") { body["sparql"] = value }
        if block("body:graphql") != nil { body["graphql"] = ["query": text("body:graphql") ?? "", "variables": text("body:graphql:vars") ?? ""] }
        body["formUrlEncoded"] = list("body:form-urlencoded")
        body["multipartForm"] = pairs(block("body:multipart-form")?.lines ?? []).map { pair -> [String: Any] in
            var value = pair.value, contentType = ""
            if let range = value.range(of: #"\s*@contentType\(([^)]*)\)\s*$"#, options: .regularExpression) { contentType = String(value[range]).replacingOccurrences(of: #"^\s*@contentType\(|\)\s*$"#, with: "", options: .regularExpression); value.removeSubrange(range) }
            if value.hasPrefix("@file("), value.hasSuffix(")") { return ["type": "file", "name": pair.name, "value": value.dropFirst(6).dropLast().split(separator: "|").map(String.init), "enabled": pair.enabled, "contentType": contentType] }
            return ["type": "text", "name": pair.name, "value": value, "enabled": pair.enabled, "contentType": contentType]
        }
        body["file"] = pairs(block("body:file")?.lines ?? []).map { pair -> [String: Any] in
            let path = pair.value.replacingOccurrences(of: #"^@file\(|\)(\s*@contentType\([^)]*\))?\s*$"#, with: "", options: .regularExpression)
            return ["filePath": path, "selected": pair.enabled]
        }
        request["body"] = body
        let authMode = line["auth"] ?? dictionary("auth")["mode"] ?? (http == nil ? "inherit" : "none")
        var auth: [String: Any] = ["mode": authMode]
        if let values = block("auth:\(authMode)").map({ pairs($0.lines).reduce(into: [String: Any]()) { $0[camel($1.name)] = $1.value } }) { auth[authMode] = values }
        if authMode == "oauth1", var values = auth["oauth1"] as? [String: Any] { values["accessTokenSecret"] = values["tokenSecret"]; auth["oauth1"] = values }
        if authMode == "apikey", var values = auth["apikey"] as? [String: Any] { values["placement"] = values["placement"] ?? "header"; auth["apikey"] = values }
        request["auth"] = auth
        request["script"] = ["req": text("script:pre-request") ?? "", "res": text("script:post-response") ?? ""]
        request["vars"] = ["req": list("vars:pre-request") + list("vars"), "res": list("vars:post-response")]
        request["assertions"] = list("assert")
        request["tests"] = text("tests") ?? ""
        if let docs = text("docs") { request["docs"] = docs; item["docs"] = docs }
        item["request"] = request
        let settings = dictionary("settings")
        var parsedSettings: [String: Any] = [:]
        if let follow = settings["followRedirects"] { parsedSettings["followRedirects"] = follow == "true" }
        if let timeout = Double(settings["timeout"] ?? "") { parsedSettings["timeout"] = timeout }
        item["settings"] = parsedSettings
        // collection.bru and folder.bru keep their defaults under `request`, like the JSON export's `root`.
        item["root"] = ["request": request, "docs": request["docs"] ?? ""]
        return item
    }

    private static func camel(_ name: String) -> String {
        let parts = name.split(separator: "_")
        guard parts.count > 1 else { return name }
        return String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}

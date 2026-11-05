import Foundation

/// `.http` and `.rest` files used by VS Code REST Client and JetBrains HTTP Client.
enum HTTPFileImport {
    private static let methods: Set = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT"]

    static func looksLikeHTTPFile(_ text: String) -> Bool {
        text.range(of: #"(?m)^(###|(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT)\s+\S+|(https?://|\{\{)\S+\s*$)"#, options: .regularExpression) != nil
    }

    static func decode(_ text: String, name: String) throws -> CollectionImport {
        var collection = RequestCollection(name: name), variables: [Field] = [], warnings: [String] = []
        var blocks: [(title: String, lines: [String])] = [("", [])]
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if line.hasPrefix("###") { blocks.append((line.dropFirst(3).trimmingCharacters(in: .whitespaces), [])) } else { blocks[blocks.count - 1].lines.append(line) }
        }
        for block in blocks {
            var lines = block.lines[...], title = block.title, followRedirects = true, preScript = ""
            // Comments, file variables and directives precede the request line.
            var requestLine: String?
            while let line = lines.first {
                lines = lines.dropFirst()
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") {
                    let comment = trimmed.drop { $0 == "#" || $0 == "/" }.trimmingCharacters(in: .whitespaces)
                    if comment.hasPrefix("@name") { title = comment.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " =")) }
                    if comment.hasPrefix("@no-redirect") { followRedirects = false }
                    continue
                }
                if trimmed.hasPrefix("@"), let equals = trimmed.firstIndex(of: "=") {
                    variables.removeAll { $0.name == trimmed[trimmed.index(after: trimmed.startIndex)..<equals].trimmingCharacters(in: .whitespaces) }
                    variables.append(Field(trimmed[trimmed.index(after: trimmed.startIndex)..<equals].trimmingCharacters(in: .whitespaces), dynamic(trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces))))
                    continue
                }
                if trimmed.hasPrefix("< {%") { preScript += script(trimmed, rest: &lines, prefix: "<"); continue }
                requestLine = trimmed; break
            }
            guard let requestLine else { continue }
            var parts = requestLine.split(separator: " ").map(String.init)
            let method = methods.contains(parts.first?.uppercased() ?? "") ? parts.removeFirst().uppercased() : "GET"
            if parts.last?.uppercased().hasPrefix("HTTP/") == true { parts.removeLast() }
            var url = dynamic(parts.joined(separator: " "))
            while let line = lines.first, let first = line.trimmingCharacters(in: .whitespaces).first, first == "?" || first == "&" { url += line.trimmingCharacters(in: .whitespaces); lines = lines.dropFirst() }
            url = url.replacingOccurrences(of: #"\s+HTTP/[\d.]+$"#, with: "", options: .regularExpression)
            var request = APIRequest(name: title.isEmpty ? "\(method) \(url)" : title, method: method, url: url)
            request.headers = []; request.followRedirects = followRedirects; request.preScript = preScript
            while let line = lines.first, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines = lines.dropFirst()
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.hasPrefix("//") { continue }
                guard let colon = trimmed.firstIndex(of: ":") else { continue }
                request.headers.append(Field(trimmed[..<colon].trimmingCharacters(in: .whitespaces), dynamic(trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces))))
            }
            var body: [String] = []
            while let line = lines.first {
                lines = lines.dropFirst()
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("> {%") { request.postScript += script(trimmed, rest: &lines, prefix: ">"); continue }
                if trimmed.hasPrefix(">") || trimmed.hasPrefix("<>") { warnings.append(String(localized: "Response handler files and saved-response references (> file.js, <> file) were not imported.", bundle: .module)); continue }
                if trimmed.hasPrefix("< ") && body.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    request.bodyKind = .file; request.fileBody = RequestFile(filename: (trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent)
                    warnings.append(String(localized: "Choose the imported body file on this device before sending.", bundle: .module)); continue
                }
                body.append(line)
            }
            while body.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeLast() }
            while body.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeFirst() }
            if !body.isEmpty && request.bodyKind == .none {
                request.body = dynamic(body.joined(separator: "\n"))
                let type = request.headers.first { $0.name.lowercased() == "content-type" }?.value.lowercased() ?? ""
                if type.contains("x-www-form-urlencoded") {
                    request.bodyKind = .form
                    request.form = request.body.replacingOccurrences(of: "\n", with: "").split(separator: "&").map { pair in
                        let item = pair.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
                        return Field(item.first ?? "", item.count > 1 ? item[1] : "")
                    }
                    request.body = ""
                } else { request.bodyKind = type.contains("json") || (type.isEmpty && (try? JSONSerialization.jsonObject(with: Data(request.body.utf8))) != nil) ? .json : .text }
                if type.contains("multipart") { request.bodyKind = .text; warnings.append(String(localized: "Multipart bodies were imported as text. Recreate them in the Multipart body editor.", bundle: .module)) }
            }
            if (request.url + request.body + request.headers.map(\.value).joined()).range(of: #"\{\{\s*\w+\.(response|request)\."#, options: .regularExpression) != nil {
                warnings.append(String(localized: "Named request references such as {{login.response.body.token}} are not resolved. Set variables from a test script instead.", bundle: .module))
            }
            if !request.preScript.isEmpty || !request.postScript.isEmpty { warnings.append(String(localized: "Imported scripts run when you send. JetBrains client, request and response objects are supported for tests, assertions and global variables.", bundle: .module)) }
            collection.requests.append(request)
        }
        guard !collection.requests.isEmpty else { throw ClientError("The HTTP file contains no requests.") }
        if !variables.isEmpty { collection.defaults = RequestDefaults(); collection.defaults?.variables = variables }
        return CollectionImport(workspace: Workspace(collections: [collection]), warnings: InterchangeImport.unique(warnings))
    }

    /// Wraps a JetBrains `{% … %}` handler so it sees that client's `client`, `request` and `response` objects.
    private static func script(_ first: String, rest: inout ArraySlice<String>, prefix: String) -> String {
        var code = String(first.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).dropFirst(2))
        while !code.contains("%}"), let line = rest.first { rest = rest.dropFirst(); code += "\n" + line }
        if let end = code.range(of: "%}", options: .backwards) { code = String(code[..<end.lowerBound]) }
        return "await (async (client, request, response) => {\n\(code.trimmingCharacters(in: .whitespacesAndNewlines))\n})(__http.client, __http.request, __http.response).catch(e => { if (!(e && e.__exit)) throw e; });\n"
    }

    /// Maps REST Client and JetBrains dynamic variables to Monkeytail's.
    static func dynamic(_ value: String) -> String {
        let names = ["$uuid": "$guid", "$random.uuid": "$guid", "$guid": "$guid", "$timestamp": "$timestamp", "$isoTimestamp": "$isoTimestamp", "$randomInt": "$randomInt", "$random.integer": "$randomInt",
                     "$datetime": "$isoTimestamp", "$localDatetime": "$isoTimestamp", "$random.email": "$randomEmail", "$random.alphanumeric": "$randomAlphaNumeric", "$random.hexadecimal": "$randomHexadecimal"]
        let pattern = try! NSRegularExpression(pattern: #"\{\{\s*(\$[\w.]+)[^}]*\}\}"#)
        var result = value
        for match in pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: value), let nameRange = Range(match.range(at: 1), in: value), let name = names[String(value[nameRange])] else { continue }
            result.replaceSubrange(range, with: "{{\(name)}}")
        }
        return result
    }
}

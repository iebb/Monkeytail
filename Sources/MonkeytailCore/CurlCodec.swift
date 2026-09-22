import Foundation

public struct CurlImport {
    public var request: APIRequest
    public var proxy: ProxySettings?
    public var warnings: [String]
}

public enum CurlCodec {
    /// A shell lexer only. Commands, substitutions, and local files are never executed.
    public static func tokens(_ source: String) throws -> [String] {
        let chars = Array(source)
        var result: [String] = [], token = "", quote: Character?, started = false, index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\\" && quote != "'" {
                index += 1
                guard index < chars.count else { throw ClientError("The cURL command ends with an incomplete escape.") }
                let next = chars[index]
                if next != "\n" {
                    if quote == "\"" && !["$", "`", "\"", "\\"].contains(next) { token.append("\\") }
                    token.append(next); started = true
                }
            } else if let current = quote {
                if char == current { quote = nil } else { token.append(char) }
            } else if char == "'" || char == "\"" {
                quote = char; started = true
            } else if char.isWhitespace {
                if started { result.append(token); token = ""; started = false }
            } else if ["|", ";", "&", "<", ">", "`"].contains(char) {
                throw ClientError("Paste a single cURL command without shell operators. Quote URLs containing &.")
            } else if char == "$" {
                throw ClientError("Shell expansions aren’t supported. Use literal values or {{environment_variables}}.")
            } else { token.append(char); started = true }
            index += 1
        }
        guard quote == nil else { throw ClientError("The cURL command contains an unclosed quote.") }
        if started { result.append(token) }
        return result
    }

    public static func decode(_ source: String) throws -> CurlImport {
        let words = try tokens(source.trimmingCharacters(in: .whitespacesAndNewlines))
        guard words.first == "curl" || words.first?.hasSuffix("/curl") == true else { throw ClientError("Start the command with curl.") }
        var request = APIRequest(name: "Imported cURL", url: "")
        request.headers = []; request.followRedirects = false
        var index = 1, explicitMethod: String?, useGet = false, head = false, data: [String] = []
        var proxy: ProxySettings?, warnings: [String] = []
        func setURL(_ value: String) throws {
            guard request.url.isEmpty else { throw ClientError("Import one URL at a time.") }
            request.url = value
        }
        while index < words.count {
            let word = words[index]
            var option = word, attached: String?
            if word.hasPrefix("--"), let equal = word.firstIndex(of: "=") {
                option = String(word[..<equal]); attached = String(word[word.index(after: equal)...])
            } else if word.count > 2, ["-X", "-H", "-d", "-u", "-A", "-b", "-e", "-x"].contains(String(word.prefix(2))) {
                option = String(word.prefix(2)); attached = String(word.dropFirst(2))
            }
            func value() throws -> String {
                if let attached { return attached }
                index += 1
                guard index < words.count else { throw ClientError("Missing value for \(option).") }
                return words[index]
            }
            switch option {
            case "-X", "--request": explicitMethod = try value().uppercased()
            case "--url": try setURL(value())
            case "-H", "--header":
                let header = try value()
                guard let colon = header.firstIndex(of: ":") else { throw ClientError("Headers must use Name: Value syntax.") }
                request.headers.append(Field(String(header[..<colon]).trimmingCharacters(in: .whitespaces), String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
            case "-d", "--data", "--data-raw", "--data-binary", "--json":
                let body = try value()
                if body.hasPrefix("@") && option != "--data-raw" { throw ClientError("File-backed cURL bodies aren’t supported. Paste the file content into the body editor.") }
                data.append(body)
                if option == "--json" {
                    request.bodyKind = .json
                    if !request.headers.contains(where: { $0.name.lowercased() == "accept" }) { request.headers.append(Field("Accept", "application/json")) }
                }
            case "--data-urlencode":
                let field = try value()
                if field.hasPrefix("@") || (!field.contains("=") && field.contains("@")) { throw ClientError("File-backed form values aren’t supported.") }
                let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                data.append(pair.count == 2 ? "\(pair[0])=\(RequestBuilder.formEncode(String(pair[1])))" : RequestBuilder.formEncode(field))
            case "-u", "--user":
                let pair = try value().split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                request.auth.kind = .basic; request.auth.username = String(pair[0]); request.auth.password = pair.count > 1 ? String(pair[1]) : ""
            case "-A", "--user-agent": request.headers.append(Field("User-Agent", try value()))
            case "-e", "--referer": request.headers.append(Field("Referer", try value()))
            case "-b", "--cookie":
                let cookie = try value()
                guard cookie.contains("=") else { throw ClientError("Cookie files aren’t supported; use a literal Cookie header.") }
                request.headers.append(Field("Cookie", cookie))
            case "-G", "--get": useGet = true
            case "-I", "--head": head = true
            case "-L", "--location": request.followRedirects = true
            case "--max-time":
                guard let timeout = Double(try value()), (1...300).contains(timeout) else { throw ClientError("Use a timeout between 1 and 300 seconds.") }
                request.timeout = timeout
            case "-x", "--proxy":
                let raw = try value()
                guard let parts = URLComponents(string: raw.contains("://") ? raw : "http://" + raw), let host = parts.host else { throw ClientError("Invalid proxy URL.") }
                var settings = ProxySettings()
                switch parts.scheme {
                case "http": settings.kind = .http
                case "https": settings.kind = .https
                case "socks5", "socks5h": settings.kind = .socks
                default: throw ClientError("Use an HTTP, HTTPS, or SOCKS5 proxy.")
                }
                settings.host = host; settings.port = String(parts.port ?? (settings.kind == .socks ? 1080 : settings.kind == .https ? 443 : 8080))
                settings.username = parts.user ?? ""; settings.password = parts.password ?? ""; proxy = settings
            case "--compressed", "-s", "-S", "-sS", "--silent", "--show-error", "--globoff", "-g": break
            case "-k", "--insecure": warnings.append("TLS certificate verification remains enabled. Install and trust your development CA in iOS Settings when needed.")
            default:
                if option.hasPrefix("-") { throw ClientError("Unsupported cURL option: \(option). Remove it before importing.") }
                try setURL(word)
            }
            index += 1
        }
        guard !request.url.isEmpty else { throw ClientError("The cURL command needs a URL.") }
        if !data.isEmpty {
            let body = data.joined(separator: "&")
            if useGet {
                request.url += (request.url.contains("?") ? "&" : "?") + body
            } else {
                request.body = body
                let type = request.headers.first(where: { $0.name.lowercased() == "content-type" })?.value ?? ""
                if request.bodyKind != .json { request.bodyKind = type.contains("json") ? .json : .text }
                if type.isEmpty && request.bodyKind != .json { request.headers.append(Field("Content-Type", "application/x-www-form-urlencoded")) }
            }
        }
        request.method = explicitMethod ?? (head ? "HEAD" : useGet || data.isEmpty ? "GET" : "POST")
        if let host = URLComponents(string: request.url)?.host { request.name = host }
        return CurlImport(request: request, proxy: proxy, warnings: warnings)
    }

    public static func encode(_ model: APIRequest, variables: [String: String] = [:]) throws -> String {
        let request = try RequestBuilder.build(model, variables: variables)
        var parts = ["curl", "--request \(quote(request.httpMethod ?? "GET"))"]
        if model.followRedirects { parts.append("--location") }
        parts.append("--max-time \(Int(model.timeout))")
        parts.append(quote(request.url!.absoluteString))
        for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            parts.append("--header \(quote(key + ": " + value))")
        }
        if let body = request.httpBody { parts.append("--data-raw \(quote(String(decoding: body, as: UTF8.self)))") }
        return parts.joined(separator: " \\\n  ")
    }
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

import Foundation

public struct CurlImport {
    public var request: APIRequest
    public var proxy: ProxySettings?
    public var warnings: [String]
}

public enum CurlCodec {
    public static func isCommand(_ word: String) -> Bool {
        let name = word.split(separator: "/").last.map(String.init) ?? word
        return ["curl", "curl-impersonate"].contains(name) || name.hasPrefix("curl_")
    }
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
        guard let command = words.first, isCommand(command) else { throw ClientError("Start the command with curl.") }
        var request = APIRequest(name: "Imported cURL", url: "")
        let name = command.split(separator: "/").last.map(String.init) ?? command
        if name.hasPrefix("curl_") { request.impersonation = BrowserImpersonation(profile: try BrowserProfile.parse(String(name.dropFirst(5)))) }
        request.headers = []; request.followRedirects = false
        var index = 1, explicitMethod: String?, useGet = false, head = false, digest = false, data: [String] = []
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
            } else if word.count > 2, ["-X", "-H", "-d", "-u", "-A", "-b", "-e", "-x", "-F"].contains(String(word.prefix(2))) {
                option = String(word.prefix(2)); attached = String(word.dropFirst(2))
            }
            func value() throws -> String {
                if let attached { return attached }
                index += 1
                guard index < words.count else { throw ClientError("Missing value for \(option).") }
                return words[index]
            }
            switch option {
            case "--impersonate":
                let parts = try value().split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count <= 2, let target = parts.first, !target.isEmpty,
                      parts.count == 1 || ["yes", "no"].contains(String(parts[1])) else { throw ClientError("Use --impersonate PROFILE or PROFILE:no to omit browser headers.") }
                request.impersonation = BrowserImpersonation(profile: try BrowserProfile.parse(String(target)), browserHeaders: parts.count == 1 || parts[1] == "yes")
            case "-X", "--request": explicitMethod = try value().uppercased()
            case "--url": try setURL(value())
            case "-H", "--header":
                let header = try value()
                guard let colon = header.firstIndex(of: ":") else { throw ClientError("Headers must use Name: Value syntax.") }
                request.headers.append(Field(String(header[..<colon]).trimmingCharacters(in: .whitespaces), String(header[header.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
            case "-d", "--data", "--data-raw", "--data-binary", "--json":
                let body = try value()
                if body.hasPrefix("@") && option != "--data-raw" {
                    guard ["--data-binary", "--json"].contains(option) else { throw ClientError("Use --data-binary @file for file uploads; --data file transformations are unsupported.") }
                    guard request.fileBody == nil, data.isEmpty, request.multipart == nil else { throw ClientError("Import one body mode at a time.") }
                    request.bodyKind = .file; request.fileBody = RequestFile(filename: String(body.dropFirst()), mimeType: option == "--json" ? "application/json" : "application/octet-stream")
                    if option == "--json", !request.headers.contains(where: { $0.name.lowercased() == "accept" }) { request.headers.append(Field("Accept", "application/json")) }
                    warnings.append(String(localized: "Choose the imported body file on this device before sending.", bundle: .module))
                    break
                }
                guard request.fileBody == nil, request.multipart == nil else { throw ClientError("Import one body mode at a time.") }
                data.append(body)
                if option == "--json" {
                    request.bodyKind = .json
                    if !request.headers.contains(where: { $0.name.lowercased() == "accept" }) { request.headers.append(Field("Accept", "application/json")) }
                }
            case "-F", "--form", "--form-string":
                guard data.isEmpty, request.fileBody == nil else { throw ClientError("Import one body mode at a time.") }
                let raw = try value()
                guard let equal = raw.firstIndex(of: "=") else { throw ClientError("Multipart fields use name=value.") }
                var part = MultipartPart(name: String(raw[..<equal]), value: String(raw[raw.index(after: equal)...]))
                if option != "--form-string", part.value.hasPrefix("@") {
                    let attributes = String(part.value.dropFirst()).split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                    guard !attributes[0].contains(","), !attributes[0].isEmpty else { throw ClientError("Import each multipart file as a separate field.") }
                    var file = RequestFile(filename: attributes[0])
                    for attribute in attributes.dropFirst() {
                        if attribute.hasPrefix("type=") { file.mimeType = String(attribute.dropFirst(5)) }
                        else if attribute.hasPrefix("filename=") { file.filename = String(attribute.dropFirst(9)) }
                        else { throw ClientError("Unsupported multipart attribute: \(attribute)") }
                    }
                    part.file = file; part.value = ""
                    warnings.append(String(localized: "Choose the imported multipart file on this device before sending.", bundle: .module))
                } else if option != "--form-string", part.value.contains(";") { throw ClientError("Multipart text attributes are unsupported; use --form-string for a literal semicolon.") } else if option != "--form-string", part.value.hasPrefix("<") { throw ClientError("Use @file for multipart attachments or --form-string for literal text.") }
                request.bodyKind = .multipart
                if request.multipart == nil { request.multipart = [] }
                request.multipart!.append(part)
            case "--data-urlencode":
                guard request.fileBody == nil, request.multipart == nil else { throw ClientError("Import one body mode at a time.") }
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
            case "--digest": digest = true
            case "--basic": digest = false
            case "-k", "--insecure": warnings.append(String(localized: "TLS certificate verification remains enabled. Install and trust your development CA in iOS Settings when needed.", bundle: .module))
            default:
                if option.hasPrefix("-") { throw ClientError("Unsupported cURL option: \(option). Remove it before importing.") }
                try setURL(word)
            }
            index += 1
        }
        if useGet && (request.fileBody != nil || request.multipart != nil) { throw ClientError("Multipart and file bodies cannot be combined with --get.") }
        guard !request.url.isEmpty else { throw ClientError("The cURL command needs a URL.") }
        if digest && request.auth.kind == .basic { request.auth.kind = .digest }
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
        request.method = explicitMethod ?? (head ? "HEAD" : useGet || (data.isEmpty && request.bodyKind == .none) ? "GET" : "POST")
        if let host = URLComponents(string: request.url)?.host { request.name = host }
        return CurlImport(request: request, proxy: proxy, warnings: warnings)
    }

    public static func encode(_ model: APIRequest, variables: [String: String] = [:]) throws -> String {
        var metadata = model
        if model.bodyKind == .multipart || model.bodyKind == .file { metadata.bodyKind = .none }
        let request = try RequestBuilder.build(metadata, variables: variables)
        var parts = [model.impersonation == nil ? "curl" : "curl-impersonate", "--request \(quote(request.httpMethod ?? "GET"))"]
        if let impersonation = model.impersonation {
            parts.append("--impersonate \(quote(impersonation.profile.rawValue + (impersonation.browserHeaders ? "" : ":no")))")
        }
        if model.followRedirects { parts.append("--location") }
        if model.auth.kind == .digest { parts.append("--digest --user \(quote(try RequestBuilder.resolve(model.auth.username + ":" + model.auth.password, variables: variables)))") }
        parts.append("--max-time \(Int(model.timeout))")
        parts.append(quote(request.url!.absoluteString))
        if model.bodyKind == .file, let file = model.fileBody, request.value(forHTTPHeaderField: "Content-Type") == nil { parts.append("--header \(quote("Content-Type: " + (try MultipartEncoder.mime(file.mimeType))))") }
        for (key, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            if model.bodyKind == .multipart && key.lowercased() == "content-type" { continue }
            parts.append("--header \(quote(key + ": " + value))")
        }
        if model.bodyKind == .multipart {
            for part in model.multipart ?? [] where part.enabled && !part.name.isEmpty {
                let name = try RequestBuilder.resolve(part.name, variables: variables)
                if let file = part.file { parts.append("--form \(quote(name + "=@" + file.filename + ";type=" + file.mimeType))") }
                else { parts.append("--form-string \(quote(name + "=" + (try RequestBuilder.resolve(part.value, variables: variables))))") }
            }
        } else if model.bodyKind == .file, let file = model.fileBody {
            parts.append("--data-binary \(quote("@" + file.filename))")
        }
        if let body = request.httpBody { parts.append("--data-raw \(quote(String(decoding: body, as: UTF8.self)))") }
        return parts.joined(separator: " \\\n  ")
    }
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

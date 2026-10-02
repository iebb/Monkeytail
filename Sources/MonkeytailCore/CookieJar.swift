import Foundation

public struct StoredCookie: Codable, Identifiable, Equatable, Sendable {
    public var name: String, value: String, domain: String, path: String
    public var secure: Bool, httpOnly: Bool, hostOnly: Bool
    public var expires: Date?
    public var created = Date()
    public var id: String { domain.lowercased() + "|" + path + "|" + name }
    public init(name: String, value: String, domain: String, path: String = "/", secure: Bool = false, httpOnly: Bool = false, hostOnly: Bool = true, expires: Date? = nil) {
        self.name = name; self.value = value; self.domain = domain.lowercased(); self.path = path; self.secure = secure; self.httpOnly = httpOnly; self.hostOnly = hostOnly; self.expires = expires
    }
    public func validated() throws -> StoredCookie {
        let token = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard !name.isEmpty, name.unicodeScalars.allSatisfy(token.contains),
              !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0.value == 59 }),
              path.hasPrefix("/"), !path.contains("\r"), !path.contains("\n"),
              !domain.isEmpty, !domain.contains(where: { $0.isWhitespace || "/:@?#".contains($0) }),
              hostOnly || !PublicSuffix.isSuffix(domain) else { throw ClientError("Enter a valid cookie name, value, domain, and path.") }
        if name.hasPrefix("__Secure-"), !secure { throw ClientError("__Secure- cookies require HTTPS only.") }
        if name.hasPrefix("__Host-"), !secure || !hostOnly || path != "/" { throw ClientError("__Host- cookies require an exact host, / path, and HTTPS only.") }
        var copy = self; copy.domain = domain.lowercased(); return copy
    }
}
public struct CookieJar: Codable, Equatable, Sendable {
    public var cookies: [StoredCookie] = []
    public init() {}
    public mutating func capture(headers: [Field], url: URL, now: Date = Date()) {
        guard let host = url.host?.lowercased() else { return }
        for field in headers where field.name.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
            // Some transports combine Set-Cookie lines; split only at a new cookie-name, never inside Expires.
            let expression = try! NSRegularExpression(pattern: #",(?=\s*[^\s;,=]+\s*=)"#)
            let value = expression.stringByReplacingMatches(in: field.value, range: NSRange(field.value.startIndex..., in: field.value), withTemplate: "\n")
            for line in value.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let pair = parts.first?.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false), pair.count == 2 else { continue }
                var cookie = StoredCookie(name: String(pair[0]), value: String(pair[1]), domain: host)
                let requestPath = url.path.isEmpty ? "/" : url.path
                cookie.path = requestPath.contains("/") ? String(requestPath.prefix(upTo: requestPath.lastIndex(of: "/")!)) : "/"
                if cookie.path.isEmpty { cookie.path = "/" }
                var maxAge: Double?
                for attribute in parts.dropFirst() {
                    let item = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard !item.isEmpty else { continue }
                    let key = item[0].lowercased(), value = item.count == 2 ? String(item[1]) : ""
                    switch key {
                    case "domain": cookie.domain = value.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased(); cookie.hostOnly = false
                    case "path": if value.hasPrefix("/") { cookie.path = value }
                    case "secure": cookie.secure = true
                    case "httponly": cookie.httpOnly = true
                    case "max-age": if let seconds = Double(value), seconds.isFinite { maxAge = max(-1, min(seconds, 400 * 86400)) }
                    case "expires":
                        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
                            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = format
                            if let date = formatter.date(from: value) { cookie.expires = date; break }
                        }
                    default: break
                    }
                }
                if let maxAge { cookie.expires = now.addingTimeInterval(maxAge) }
                // Restrict domain cookies to this host or its parent, excluding bare public suffixes.
                guard cookie.hostOnly || (!PublicSuffix.isSuffix(cookie.domain) && (host == cookie.domain || (!host.split(separator: ".").allSatisfy({ UInt8($0) != nil }) && host.hasSuffix("." + cookie.domain)))) else { continue }
                guard let valid = try? cookie.validated() else { continue }; cookie = valid
                if cookie.name.hasPrefix("__Secure-"), !cookie.secure || url.scheme != "https" { continue }
                if cookie.name.hasPrefix("__Host-"), !cookie.secure || !cookie.hostOnly || cookie.path != "/" || url.scheme != "https" { continue }
                if url.scheme != "https", cookies.contains(where: { $0.secure && $0.name == cookie.name && ($0.domain == cookie.domain || cookie.domain.hasSuffix("." + $0.domain)) }) { continue }
                cookies.removeAll { $0.id == cookie.id }
                if cookie.expires.map({ $0 > now }) ?? true { cookies.append(cookie) }
            }
        }
        cookies.removeAll { $0.expires.map { $0 <= now } ?? false }
        if cookies.count > 300 { cookies = Array(cookies.suffix(300)) }
    }
    public func header(for url: URL, now: Date = Date()) -> String {
        let host = url.host?.lowercased() ?? "", path = url.path.isEmpty ? "/" : url.path
        return cookies.filter { c in
            (c.hostOnly ? host == c.domain : host == c.domain || host.hasSuffix("." + c.domain)) &&
            (path == c.path || path.hasPrefix(c.path.hasSuffix("/") ? c.path : c.path + "/")) &&
            (!c.secure || url.scheme == "https") && (c.expires.map { $0 > now } ?? true)
        }.sorted { $0.path.count == $1.path.count ? $0.created < $1.created : $0.path.count > $1.path.count }.map { $0.name + "=" + $0.value }.joined(separator: "; ")
    }
}

private enum PublicSuffix {
    static let rules: Set<String> = {
        guard let url = Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat"), let text = try? String(contentsOf: url) else { return ["com", "org", "net", "co.uk"] }
        return Set(text.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("//") }.map { $0.lowercased() })
    }()
    static func isSuffix(_ domain: String) -> Bool {
        if !domain.contains(".") { return true }
        if rules.contains("!" + domain) { return false }
        if rules.contains(domain) { return true }
        let labels = domain.split(separator: ".")
        if labels.count > 1, rules.contains("*." + labels.dropFirst().joined(separator: ".")) { return true }
        return false
    }
}

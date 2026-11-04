import Foundation
import CryptoKit

public struct DigestChallenge: Equatable, Sendable {
    public var realm = "", nonce = "", opaque: String?, algorithm = "MD5", qop: [String] = [], stale = false
    public init() {}
}

/// HTTP Digest authentication (RFC 7616, RFC 2617) answered after a 401 challenge.
public enum DigestAuth {
    public static func challenge(from headers: [Field]) -> DigestChallenge? {
        headers.filter { $0.name.caseInsensitiveCompare("WWW-Authenticate") == .orderedSame }.lazy.compactMap { parse($0.value) }.first
    }
    public static func parse(_ header: String) -> DigestChallenge? {
        guard let start = header.range(of: "digest ", options: .caseInsensitive) else { return nil }
        let chars = Array(header[start.upperBound...])
        var index = 0, values: [String: String] = [:]
        while index < chars.count {
            while index < chars.count, chars[index] == "," || chars[index].isWhitespace { index += 1 }
            var key = ""
            while index < chars.count, chars[index] != "=", chars[index] != ",", !chars[index].isWhitespace { key.append(chars[index]); index += 1 }
            while index < chars.count, chars[index].isWhitespace { index += 1 }
            guard index < chars.count, chars[index] == "=", !key.isEmpty else { break }
            index += 1
            while index < chars.count, chars[index].isWhitespace { index += 1 }
            var value = ""
            if index < chars.count, chars[index] == "\"" {
                index += 1
                while index < chars.count, chars[index] != "\"" {
                    if chars[index] == "\\", index + 1 < chars.count { index += 1 }
                    value.append(chars[index]); index += 1
                }
                index += 1
            } else {
                while index < chars.count, chars[index] != ",", !chars[index].isWhitespace { value.append(chars[index]); index += 1 }
            }
            values[key.lowercased()] = value
        }
        guard let nonce = values["nonce"] else { return nil }
        var result = DigestChallenge()
        result.realm = values["realm"] ?? ""; result.nonce = nonce; result.opaque = values["opaque"]
        result.algorithm = values["algorithm"] ?? "MD5"; result.stale = values["stale"]?.lowercased() == "true"
        result.qop = (values["qop"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        return result
    }
    public static func authorization(_ challenge: DigestChallenge, username: String, password: String, method: String, uri: String, body: Data? = nil,
                                     cnonce: String = randomCnonce(), nonceCount: Int = 1) throws -> String {
        guard !(username + password + uri).unicodeScalars.contains(where: { $0.value == 10 || $0.value == 13 }) else { throw ClientError("Invalid Digest credentials.") }
        let algorithm = challenge.algorithm.uppercased(), session = algorithm.hasSuffix("-SESS")
        let digest: (Data) -> String
        switch session ? String(algorithm.dropLast(5)) : algorithm {
        case "MD5": digest = { hex(Insecure.MD5.hash(data: $0)) }
        case "SHA-256": digest = { hex(SHA256.hash(data: $0)) }
        default: throw ClientError("Digest algorithm \(challenge.algorithm) is unsupported. Use MD5 or SHA-256.")
        }
        let hash = { (text: String) in digest(Data(text.utf8)) }
        let qop = challenge.qop.contains("auth") ? "auth" : challenge.qop.contains("auth-int") ? "auth-int" : nil
        guard challenge.qop.isEmpty || qop != nil else { throw ClientError("Digest qop \(challenge.qop.joined(separator: ", ")) is unsupported.") }
        let nc = String(format: "%08x", nonceCount)
        var ha1 = hash("\(username):\(challenge.realm):\(password)")
        if session { ha1 = hash("\(ha1):\(challenge.nonce):\(cnonce)") }
        let ha2 = qop == "auth-int" ? hash("\(method):\(uri):" + digest(body ?? Data())) : hash("\(method):\(uri)")
        let response = qop.map { hash("\(ha1):\(challenge.nonce):\(nc):\(cnonce):\($0):\(ha2)") } ?? hash("\(ha1):\(challenge.nonce):\(ha2)")
        var parts = ["username=\(quote(username))", "realm=\(quote(challenge.realm))", "nonce=\(quote(challenge.nonce))", "uri=\(quote(uri))", "algorithm=\(challenge.algorithm)"]
        if let qop { parts += ["qop=\(qop)", "nc=\(nc)", "cnonce=\(quote(cnonce))"] }
        parts.append("response=\(quote(response))")
        if let opaque = challenge.opaque { parts.append("opaque=\(quote(opaque))") }
        return "Digest " + parts.joined(separator: ", ")
    }
    /// The request-target used in the digest: path plus query.
    public static func uri(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? "/"
        return (path.isEmpty ? "/" : path) + (components?.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
    public static func randomCnonce() -> String { hex((0..<16).map { _ in UInt8.random(in: 0...255) }) }
    private static func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 { bytes.map { String(format: "%02x", $0) }.joined() }
}

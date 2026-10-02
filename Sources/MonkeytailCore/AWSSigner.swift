import Foundation
import CryptoKit

public enum AWSSigner {
    public static func sign(_ source: URLRequest, credentials: AWSAuth, date: Date = Date()) throws -> URLRequest {
        guard let url = source.url, let host = url.host, !credentials.accessKey.isEmpty, !credentials.secretKey.isEmpty,
              !credentials.region.isEmpty, !credentials.service.isEmpty else { throw ClientError("AWS requires access key, secret key, region, and service.") }
        var request = source
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: date), day = String(timestamp.prefix(8))
        let payload = hex(SHA256.hash(data: source.httpBody ?? Data()))
        request.setValue(timestamp, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(payload, forHTTPHeaderField: "X-Amz-Content-Sha256")
        request.setValue(host + (url.port.map { ":\($0)" } ?? ""), forHTTPHeaderField: "Host")
        request.setValue(credentials.sessionToken.isEmpty ? nil : credentials.sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        let transportHeaders = Set(["connection", "transfer-encoding", "content-length", "user-agent", "accept-encoding", "expect", "proxy-authorization"])
        let headers = (request.allHTTPHeaderFields ?? [:]).filter { !transportHeaders.contains($0.key.lowercased()) }.map { (key: $0.key.lowercased(), value: $0.value.split(whereSeparator: \.isWhitespace).joined(separator: " ")) }.sorted { $0.key < $1.key }
        let signed = headers.map(\.key).joined(separator: ";")
        let canonicalHeaders = headers.map { $0.key + ":" + $0.value + "\n" }.joined()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        // Encode each segment independently so encoded slashes remain part of a segment.
        var encodedPath = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if credentials.service != "s3" {
            var segments: [String] = []
            for segment in encodedPath.split(separator: "/") {
                let decoded = segment.removingPercentEncoding ?? String(segment)
                if decoded == "." { continue }
                if decoded == ".." { if !segments.isEmpty { segments.removeLast() }; continue }
                segments.append(String(segment))
            }
            let trailing = encodedPath.hasSuffix("/") || encodedPath.hasSuffix("/.") || encodedPath.hasSuffix("/..")
            encodedPath = "/" + segments.joined(separator: "/") + (trailing && !segments.isEmpty ? "/" : "")
        }
        let path = encodedPath.split(separator: "/", omittingEmptySubsequences: false).map { encode($0.removingPercentEncoding ?? String($0)) }.joined(separator: "/")
        let canonicalPath = credentials.service == "s3" ? path : encode(path, keepSlash: true)
        let pairs: [(String, String)] = (components.queryItems ?? []).map { (encode($0.name), encode($0.value ?? "")) }
        let sortedPairs = pairs.sorted { a, b in a.0 == b.0 ? a.1 < b.1 : a.0 < b.0 }
        let query = sortedPairs.map { $0.0 + "=" + $0.1 }.joined(separator: "&")
        let canonical = [request.httpMethod ?? "GET", canonicalPath, query, canonicalHeaders, signed, payload].joined(separator: "\n")
        let scope = "\(day)/\(credentials.region)/\(credentials.service)/aws4_request"
        let toSign = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(hex(SHA256.hash(data: Data(canonical.utf8))))"
        let dayKey = hmac(Data(("AWS4" + credentials.secretKey).utf8), day)
        let region = hmac(dayKey, credentials.region), service = hmac(region, credentials.service), signing = hmac(service, "aws4_request")
        request.setValue("AWS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(scope), SignedHeaders=\(signed), Signature=\(hex(hmac(signing, toSign)))", forHTTPHeaderField: "Authorization")
        return request
    }
    private static func encode(_ value: String, keepSlash: Bool = false) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~" + (keepSlash ? "/" : ""))) ?? value }
    private static func hmac(_ key: Data, _ value: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key))) }
    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 { bytes.map { String(format: "%02x", $0) }.joined() }
}

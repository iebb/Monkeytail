import Foundation
import CryptoKit

/// RFC 5849 request signing, as Postman's OAuth 1.0 helper sends it in the Authorization header.
public enum OAuth1Signer {
    public static func sign(_ source: URLRequest, credentials: OAuth1Auth, nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""), date: Date = Date()) throws -> URLRequest {
        guard let url = source.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(),
              !credentials.consumerKey.isEmpty else { throw ClientError("OAuth 1.0 requires a consumer key.") }
        var oauth = [("oauth_consumer_key", credentials.consumerKey), ("oauth_nonce", nonce), ("oauth_signature_method", credentials.signatureMethod.rawValue),
                     ("oauth_timestamp", String(Int(date.timeIntervalSince1970))), ("oauth_version", "1.0")]
        if !credentials.token.isEmpty { oauth.append(("oauth_token", credentials.token)) }
        var parameters = oauth + (components.percentEncodedQueryItems ?? []).map { (decode($0.name), decode($0.value ?? "")) }
        if source.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/x-www-form-urlencoded") == true, let body = source.httpBody.flatMap({ String(data: $0, encoding: .utf8) }), !body.isEmpty {
            parameters += body.split(separator: "&").map { pair in let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false); return (decode(String(parts[0])), decode(parts.count > 1 ? String(parts[1]) : "")) }
        }
        let encoded: [(String, String)] = parameters.map { (encode($0.0), encode($0.1)) }
        let normalized = encoded.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        let defaultPort = (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443)
        let baseURL = scheme + "://" + host + (components.port.map { defaultPort ? "" : ":\($0)" } ?? "") + (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)
        let base = [(source.httpMethod ?? "GET").uppercased(), encode(baseURL), encode(normalized)].joined(separator: "&")
        let key = encode(credentials.consumerSecret) + "&" + encode(credentials.tokenSecret)
        let signature: String
        switch credentials.signatureMethod {
        case .hmacSHA1: signature = Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(base.utf8), using: SymmetricKey(data: Data(key.utf8)))).base64EncodedString()
        case .hmacSHA256: signature = Data(HMAC<SHA256>.authenticationCode(for: Data(base.utf8), using: SymmetricKey(data: Data(key.utf8)))).base64EncodedString()
        case .plaintext: signature = key
        }
        let fields = (credentials.realm.isEmpty ? [] : [("realm", credentials.realm)]) + oauth + [("oauth_signature", signature)]
        var request = source
        request.setValue("OAuth " + fields.map { "\(encode($0.0))=\"\(encode($0.1))\"" }.joined(separator: ", "), forHTTPHeaderField: "Authorization")
        return request
    }
    static func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? value }
    private static func decode(_ value: String) -> String { value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value }
}

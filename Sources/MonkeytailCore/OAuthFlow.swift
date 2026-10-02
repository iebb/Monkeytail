import Foundation
import CryptoKit
import Security

public enum OAuthFlow {
    public static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ClientError("Could not generate OAuth state.") }
        return base64URL(Data(bytes))
    }
    public static func challenge(_ verifier: String) -> String { base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public static func authorizationURL(_ config: OAuthConfiguration, state: String, verifier: String) throws -> URL {
        guard var url = URLComponents(string: config.authorizationURL), ["https", "http"].contains(url.scheme ?? ""), url.host != nil, !config.clientID.isEmpty,
              let callback = URLComponents(string: config.callbackURL), callback.scheme == "monkeytail", callback.host == "oauth" else { throw ClientError("Enter an authorization URL, client ID, and monkeytail://oauth callback.") }
        let values = ["response_type": "code", "client_id": config.clientID, "redirect_uri": config.callbackURL, "scope": config.scope, "state": state, "code_challenge": challenge(verifier), "code_challenge_method": "S256"]
        url.queryItems = (url.queryItems ?? []).filter { values[$0.name] == nil } + values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let result = url.url else { throw ClientError("Invalid OAuth URL.") }; return result
    }
    public static func code(from callback: URL, config: OAuthConfiguration, state: String) throws -> String {
        guard let expected = URLComponents(string: config.callbackURL), let received = URLComponents(url: callback, resolvingAgainstBaseURL: false), expected.scheme == received.scheme, expected.host == received.host, expected.path == received.path else { throw ClientError("OAuth callback does not match the registered redirect URI.") }
        let parameters = received.queryItems ?? []
        guard parameters.filter({ $0.name == "state" }).count == 1, parameters.first(where: { $0.name == "state" })?.value == state else { throw ClientError("OAuth state did not match.") }
        guard parameters.first(where: { $0.name == "error" }) == nil, parameters.filter({ $0.name == "code" }).count == 1, let code = parameters.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw ClientError("API authorization was declined or returned no code.") }; return code
    }
    public static func tokenRequest(_ config: OAuthConfiguration, code: String? = nil, verifier: String? = nil, refresh: Bool = false) throws -> URLRequest {
        guard let url = URL(string: config.tokenURL), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw ClientError("Enter an HTTP or HTTPS token endpoint.") }
        var fields = ["client_id": config.clientID]
        if !config.clientSecret.isEmpty { fields["client_secret"] = config.clientSecret }
        if refresh {
            guard !config.refreshToken.isEmpty else { throw ClientError("No refresh token is available.") }
            fields["grant_type"] = "refresh_token"; fields["refresh_token"] = config.refreshToken
        } else if config.grant == .clientCredentials { fields["grant_type"] = "client_credentials"; fields["scope"] = config.scope }
        else {
            guard let code, let verifier else { throw ClientError("Complete API authorization first.") }
            fields["grant_type"] = "authorization_code"; fields["code"] = code; fields["code_verifier"] = verifier; fields["redirect_uri"] = config.callbackURL
        }
        var request = URLRequest(url: url, timeoutInterval: 30); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { RequestBuilder.formEncode($0.key) + "=" + RequestBuilder.formEncode($0.value) }.joined(separator: "&").utf8)
        return request
    }
    public static func apply(_ response: APIResponse, to source: OAuthConfiguration, now: Date = Date()) throws -> OAuthConfiguration {
        guard (200...299).contains(response.status), let object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any], let access = object["access_token"] as? String, !access.isEmpty else { throw ClientError("Token endpoint did not return an access token (HTTP \(response.status)).") }
        if let type = object["token_type"] as? String, type.lowercased() != "bearer" { throw ClientError("Only OAuth bearer tokens are supported.") }
        var result = source; result.accessToken = access
        if let refresh = object["refresh_token"] as? String { result.refreshToken = refresh }
        if let expires = object["expires_in"] as? Double { result.expiresAt = now.addingTimeInterval(max(0, expires)) }
        else if let expires = object["expires_in"] as? String, let seconds = Double(expires) { result.expiresAt = now.addingTimeInterval(max(0, seconds)) }
        else { result.expiresAt = nil }
        return result
    }
    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

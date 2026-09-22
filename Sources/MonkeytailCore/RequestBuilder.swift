import Foundation

public enum RequestBuilder {
    public static func resolve(_ text: String, variables: [String: String]) throws -> String {
        let regex = try NSRegularExpression(pattern: #"\{\{\s*([\w.\-]+)\s*\}\}"#)
        var result = text
        // Resolve nested variables, with a finite bound for cycles.
        for _ in 0..<10 {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            if matches.isEmpty { return result }
            for match in matches.reversed() {
                guard let keyRange = Range(match.range(at: 1), in: result), let range = Range(match.range, in: result) else { continue }
                let key = String(result[keyRange])
                guard let value = variables[key] else { throw ClientError("Missing environment variable: \(key)") }
                result.replaceSubrange(range, with: value)
            }
        }
        throw ClientError("Environment variables contain a cycle or are nested too deeply.")
    }

    public static func build(_ model: APIRequest, variables: [String: String] = [:]) throws -> URLRequest {
        let rawURL = try resolve(model.url.trimmingCharacters(in: .whitespacesAndNewlines), variables: variables)
        guard var components = URLComponents(string: rawURL), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty else { throw ClientError("Enter a complete http:// or https:// URL.") }
        let fields = try model.query.filter { $0.enabled && !$0.name.isEmpty }.map {
            try formEncode(resolve($0.name, variables: variables)) + "=" + formEncode(resolve($0.value, variables: variables))
        }
        if !fields.isEmpty {
            let existing = components.percentEncodedQuery.map { $0.isEmpty ? "" : $0 + "&" } ?? ""
            components.percentEncodedQuery = existing + fields.joined(separator: "&")
        }
        guard let url = components.url else { throw ClientError("The URL could not be encoded.") }
        let method = model.method.uppercased()
        guard isToken(method), !method.isEmpty else { throw ClientError("Invalid HTTP method.") }
        guard (1...300).contains(model.timeout) else { throw ClientError("Timeout must be between 1 and 300 seconds.") }
        var request = URLRequest(url: url, timeoutInterval: model.timeout)
        request.httpMethod = method
        for field in model.headers where field.enabled && !field.name.isEmpty {
            let name = try resolve(field.name, variables: variables)
            let value = try resolve(field.value, variables: variables)
            guard isToken(name), !value.unicodeScalars.contains(where: { $0.value == 10 || $0.value == 13 }) else { throw ClientError("Invalid header: \(name)") }
            request.addValue(value, forHTTPHeaderField: name)
        }
        switch model.auth.kind {
        case .none: break
        case .bearer:
            let token = try resolve(model.auth.token, variables: variables)
            guard !token.unicodeScalars.contains(where: { $0.value == 10 || $0.value == 13 }) else { throw ClientError("Invalid bearer token.") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .basic:
            let credentials = try resolve("\(model.auth.username):\(model.auth.password)", variables: variables)
            request.setValue("Basic \(Data(credentials.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        switch model.bodyKind {
        case .none: break
        case .json, .text:
            let body = try resolve(model.body, variables: variables)
            if model.bodyKind == .json { _ = try JSONTools.parse(body) }
            request.httpBody = Data(body.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue(model.bodyKind == .json ? "application/json" : "text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        case .form:
            let encoded = try model.form.filter { $0.enabled && !$0.name.isEmpty }.map {
                try formEncode(resolve($0.name, variables: variables)) + "=" + formEncode(resolve($0.value, variables: variables))
            }.joined(separator: "&")
            request.httpBody = Data(encoded.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        }
        return request
    }

    public static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? value
    }

    private static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }
    }
}

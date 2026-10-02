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
        var query = model.query
        if model.auth.kind == .apiKey, let key = model.auth.apiKey, key.inQuery { query.append(Field(key.name, key.value)) }
        let fields = try query.filter { $0.enabled && !$0.name.isEmpty }.map {
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
        case .inherit: throw ClientError("Resolve inherited authentication before building the request.")
        case .apiKey:
            if let key = model.auth.apiKey, !key.inQuery {
                let name = try resolve(key.name, variables: variables), value = try resolve(key.value, variables: variables)
                guard isToken(name), !value.contains("\r"), !value.contains("\n") else { throw ClientError("Invalid API key header.") }
                request.setValue(value, forHTTPHeaderField: name)
            }
        case .oauth2:
            let token = try resolve(model.auth.oauth?.accessToken ?? model.auth.token, variables: variables)
            guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { throw ClientError("Get an OAuth access token before sending.") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .aws: break
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
        case .multipart:
            let boundary = "Monkeytail-" + UUID().uuidString
            request.httpBody = try MultipartEncoder.encode(model.multipart ?? [], boundary: boundary, variables: variables)
            // The boundary must match the bytes, even when importing a captured header.
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        case .file:
            guard let file = model.fileBody, let data = file.data else { throw ClientError("Choose a body file before sending.") }
            guard data.count <= MultipartEncoder.maximumBytes else { throw ClientError("Upload exceeds the 20 MB limit.") }
            request.httpBody = data
            if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue(try MultipartEncoder.mime(file.mimeType), forHTTPHeaderField: "Content-Type") }
        }
        if model.transport == .graphql {
            request.httpBody = try (model.graphql ?? GraphQLRequest()).body(values: variables)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let schema = model.requestSchema, !schema.isEmpty, let body = request.httpBody {
            let errors = try JSONSchema.validate(body, schema: schema)
            if !errors.isEmpty { throw ClientError("Request schema: " + errors.prefix(5).joined(separator: "; ")) }
        }
        if let body = request.httpBody, body.count > MultipartEncoder.maximumBytes { throw ClientError("Upload exceeds the 20 MB limit.") }
        if model.auth.kind == .aws {
            var auth = model.auth.aws ?? AWSAuth()
            auth.accessKey = try resolve(auth.accessKey, variables: variables); auth.secretKey = try resolve(auth.secretKey, variables: variables)
            auth.sessionToken = try resolve(auth.sessionToken, variables: variables); auth.region = try resolve(auth.region, variables: variables); auth.service = try resolve(auth.service, variables: variables)
            request = try AWSSigner.sign(request, credentials: auth)
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

import Foundation

public enum CodeLanguage: String, CaseIterable, Identifiable, Sendable { case swift = "Swift URLSession", javascript = "JavaScript fetch", python = "Python requests", kotlin = "Kotlin OkHttp"; public var id: String { rawValue } }
public enum CodeGenerator {
    public static func generate(_ model: APIRequest, variables: [String: String], language: CodeLanguage, redact: Bool = true) throws -> String {
        guard model.transport != .websocket && model.transport != .sse else { throw ClientError("Code generation currently supports HTTP and GraphQL requests.") }
        var model = model
        if redact {
            for index in model.form.indices where model.form[index].isSecret || SecretPolicy.isSensitive(model.form[index].name) { model.form[index].value = "<SECRET>" }
            for index in (model.multipart ?? []).indices where SecretPolicy.isSensitive(model.multipart![index].name) && model.multipart![index].file == nil { model.multipart![index].value = "<SECRET>" }
        }
        if redact, model.auth.kind == .oauth2, model.auth.oauth?.accessToken.isEmpty != false { if model.auth.oauth == nil { model.auth.oauth = OAuthConfiguration() }; model.auth.oauth?.accessToken = "<ACCESS_TOKEN>" }
        var request = try RequestBuilder.build(model, variables: variables)
        guard (request.httpBody?.count ?? 0) <= 1024 * 1024 else { throw ClientError("Code generation is limited to 1 MB bodies. Export larger attachments separately.") }
        if redact {
            for key in (request.allHTTPHeaderFields ?? [:]).keys where SecretPolicy.isSensitive(key) { request.setValue("<" + key.uppercased() + ">", forHTTPHeaderField: key) }
            if model.auth.kind == .apiKey, let key = model.auth.apiKey, !key.inQuery { request.setValue("<API_KEY>", forHTTPHeaderField: key.name) }
            for field in model.headers where field.isSecret { let name = try RequestBuilder.resolve(field.name, variables: variables); request.setValue("<SECRET>", forHTTPHeaderField: name) }
            if var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) {
                if url.user != nil { url.user = "USERNAME" }; if url.password != nil { url.password = "PASSWORD" }
                url.queryItems = url.queryItems?.map { item in var item = item; if SecretPolicy.isSensitive(item.name) || (model.auth.kind == .apiKey && model.auth.apiKey?.inQuery == true && item.name == model.auth.apiKey?.name) { item.value = "<SECRET>" }; return item }
                request.url = url.url
            }
            if let body = request.httpBody, model.bodyKind == .json || model.transport == .graphql, let json = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
                func clean(_ value: Any) -> Any {
                    if let object = value as? [String: Any] { return object.mapValues { clean($0) }.reduce(into: [String: Any]()) { result, item in result[item.key] = SecretPolicy.isSensitive(item.key) ? "<SECRET>" : item.value } }
                    if let array = value as? [Any] { return array.map(clean) }; return value
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: clean(json), options: [.sortedKeys, .fragmentsAllowed])
            }
        }
        func q(_ value: String) -> String {
            if language == .swift {
                return "\"" + value.unicodeScalars.map { scalar -> String in
                    switch scalar.value { case 34: return "\\\""; case 92: return "\\\\"; case 10: return "\\n"; case 13: return "\\r"; case 9: return "\\t"; case 0..<32, 127: return "\\u{" + String(scalar.value, radix: 16) + "}"; default: return String(scalar) }
                }.joined() + "\""
            }
            return String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
        }
        let url = q(request.url!.absoluteString), method = q(request.httpMethod ?? "GET"), headers = (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }, body = request.httpBody
        switch language {
        case .swift:
            let headerCode = headers.map { "request.setValue(\(q($0.value)), forHTTPHeaderField: \(q($0.key)))" }.joined(separator: "\n")
            return "import Foundation\n\nvar request = URLRequest(url: URL(string: \(url))!)\nrequest.httpMethod = \(method)\nrequest.timeoutInterval = \(model.timeout)\n\(headerCode)\n" + (body.map { "request.httpBody = Data(base64Encoded: \(q($0.base64EncodedString())))\n" } ?? "") + "\nlet (data, response) = try await URLSession.shared.data(for: request)\nprint((response as? HTTPURLResponse)?.statusCode ?? 0)\nprint(String(decoding: data, as: UTF8.self))\n"
        case .javascript:
            let headerCode = headers.map { "    \(q($0.key)): \(q($0.value))" }.joined(separator: ",\n")
            return "const response = await fetch(\(url), {\n  method: \(method),\n  redirect: \(q(model.followRedirects ? "follow" : "manual")),\n  signal: AbortSignal.timeout(\(Int(model.timeout * 1000))),\n  headers: {\n\(headerCode)\n  }" + (body.map { ",\n  body: Uint8Array.from(atob(\(q($0.base64EncodedString()))), c => c.charCodeAt(0))" } ?? "") + "\n});\nconsole.log(response.status, await response.text());\n"
        case .python:
            let headerCode = headers.map { "    \(q($0.key)): \(q($0.value))" }.joined(separator: ",\n")
            return "import requests\nimport base64\n\nresponse = requests.request(\n    \(method), \(url),\n    headers={\n\(headerCode)\n    },\n    timeout=\(Int(model.timeout)),\n    allow_redirects=\(model.followRedirects ? "True" : "False")" + (body.map { ",\n    data=base64.b64decode(\(q($0.base64EncodedString())))" } ?? "") + "\n)\nprint(response.status_code)\nprint(response.text)\n"
        case .kotlin:
            func kq(_ value: String) -> String { q(value).replacingOccurrences(of: "$", with: "\\$") }
            let headerCode = headers.map { "    .addHeader(\(kq($0.key)), \(kq($0.value)))" }.joined(separator: "\n")
            let bodyCode = body.map { "Base64.getDecoder().decode(\(kq($0.base64EncodedString()))).toRequestBody()" } ?? (["POST", "PUT", "PATCH"].contains(request.httpMethod ?? "GET") ? "ByteArray(0).toRequestBody()" : "null")
            return "// Requires OkHttp 4.x or newer.\nimport okhttp3.*\nimport okhttp3.RequestBody.Companion.toRequestBody\nimport java.util.Base64\nimport java.util.concurrent.TimeUnit\n\nval client = OkHttpClient.Builder()\n    .callTimeout(\(Int(model.timeout)), TimeUnit.SECONDS)\n    .followRedirects(\(model.followRedirects))\n    .build()\nval request = Request.Builder()\n    .url(\(kq(request.url!.absoluteString)))\n\(headerCode)\n    .method(\(method), \(bodyCode))\n    .build()\nclient.newCall(request).execute().use { response ->\n    println(response.code)\n    println(response.body?.string())\n}\n"
        }
    }
}

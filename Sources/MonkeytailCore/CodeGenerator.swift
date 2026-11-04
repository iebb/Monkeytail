import Foundation

public enum CodeLanguage: String, CaseIterable, Identifiable, Sendable {
    case curl = "cURL", javascript = "JavaScript fetch", axios = "Node.js axios", python = "Python requests", go = "Go net/http", java = "Java HttpClient", csharp = "C# HttpClient"
    case php = "PHP cURL", ruby = "Ruby Net::HTTP", swift = "Swift URLSession", kotlin = "Kotlin OkHttp", httpie = "HTTPie", powershell = "PowerShell"
    public var id: String { rawValue }
}
public enum CodeGenerator {
    public static func generate(_ model: APIRequest, variables: [String: String], language: CodeLanguage, redact: Bool = true) throws -> String {
        guard model.transport != .websocket && model.transport != .sse else { throw ClientError("Code generation currently supports HTTP and GraphQL requests.") }
        var model = model
        if redact {
            for index in model.form.indices where model.form[index].isSecret || SecretPolicy.isSensitive(model.form[index].name) { model.form[index].value = "<SECRET>" }
            for index in (model.multipart ?? []).indices where SecretPolicy.isSensitive(model.multipart![index].name) && model.multipart![index].file == nil { model.multipart![index].value = "<SECRET>" }
        }
        if redact, model.auth.kind == .oauth2, model.auth.oauth?.accessToken.isEmpty != false { if model.auth.oauth == nil { model.auth.oauth = OAuthConfiguration() }; model.auth.oauth?.accessToken = "<ACCESS_TOKEN>" }
        // Redacted snippets never sign a JWT; the placeholder keeps the header or query parameter shape.
        let redactedJWT = redact && model.auth.kind == .jwt ? model.auth.jwt ?? JWTAuth() : nil
        if let jwt = redactedJWT { model.auth.kind = .none; if jwt.inQuery { model.query.append(Field(jwt.queryKey.isEmpty ? "token" : jwt.queryKey, "<JWT>")) } else { model.headers.append(Field("Authorization", jwt.headerPrefix.isEmpty ? "<JWT>" : jwt.headerPrefix + " <JWT>")) } }
        var request = try RequestBuilder.build(model, variables: variables)
        guard (request.httpBody?.count ?? 0) <= 1024 * 1024 else { throw ClientError("Code generation is limited to 1 MB bodies. Export larger attachments separately.") }
        if redact {
            for key in (request.allHTTPHeaderFields ?? [:]).keys where SecretPolicy.isSensitive(key) { request.setValue("<" + key.uppercased() + ">", forHTTPHeaderField: key) }
            if model.auth.kind == .apiKey, let key = model.auth.apiKey, !key.inQuery { request.setValue("<API_KEY>", forHTTPHeaderField: key.name) }
            for field in model.headers where field.isSecret { let name = try RequestBuilder.resolve(field.name, variables: variables); request.setValue("<SECRET>", forHTTPHeaderField: name) }
            if let jwt = redactedJWT, !jwt.inQuery { request.setValue(try RequestBuilder.resolve(jwt.headerPrefix.isEmpty ? "<JWT>" : jwt.headerPrefix + " <JWT>", variables: variables), forHTTPHeaderField: "Authorization") }
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
        let rawURL = request.url!.absoluteString, rawMethod = request.httpMethod ?? "GET"
        let url = q(rawURL), method = q(rawMethod), headers = (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }, body = request.httpBody
        // Printable UTF-8 bodies stay readable; other bytes are embedded as base64.
        let text = body.flatMap { data -> String? in
            guard let value = String(data: data, encoding: .utf8), !value.unicodeScalars.contains(where: { ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127 }) else { return nil }
            return value
        }
        let base64 = text == nil ? body?.base64EncodedString() : nil, timeout = Int(model.timeout)
        let sh = CurlCodec.quote
        func single(_ value: String, escapingBackslash: Bool) -> String { "'" + (escapingBackslash ? value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") : value.replacingOccurrences(of: "'", with: "''")) + "'" }
        switch language {
        case .curl:
            var parts = ["curl --request \(sh(rawMethod))", "--url \(sh(rawURL))", "--max-time \(timeout)"]
            if model.followRedirects { parts.insert("--location", at: 1) }
            parts += headers.map { "--header \(sh($0.key + ": " + $0.value))" }
            if let text { parts.append("--data-raw \(sh(text))") }
            if let base64 { parts.append("--data-binary @-") }
            return (base64.map { "printf %s \(sh($0)) | base64 --decode | " } ?? "") + parts.joined(separator: " \\\n  ") + "\n"
        case .axios:
            var options = ["  method: \(method)", "  url: \(url)", "  headers: {\n" + headers.map { "    \(q($0.key)): \(q($0.value))" }.joined(separator: ",\n") + "\n  }", "  timeout: \(timeout * 1000)", "  responseType: 'text'", "  validateStatus: () => true"]
            if !model.followRedirects { options.append("  maxRedirects: 0") }
            if let text { options.append("  data: \(q(text))") }
            if let base64 { options.append("  data: Buffer.from(\(q(base64)), 'base64')") }
            return "const axios = require('axios');\n\naxios.request({\n" + options.joined(separator: ",\n") + "\n}).then(response => {\n  console.log(response.status);\n  console.log(response.data);\n});\n"
        case .go:
            var imports = ["fmt", "io", "net/http", "time"]
            if text != nil { imports.append("strings") }
            if base64 != nil { imports += ["bytes", "encoding/base64"] }
            var lines = ["func main() {"]
            if let base64 { lines.append("\tpayload, err := base64.StdEncoding.DecodeString(\(q(base64)))\n\tif err != nil {\n\t\tpanic(err)\n\t}") }
            let reader = text.map { "strings.NewReader(\(q($0)))" } ?? (base64 != nil ? "bytes.NewReader(payload)" : "nil")
            lines.append("\treq, err := http.NewRequest(\(method), \(url), \(reader))\n\tif err != nil {\n\t\tpanic(err)\n\t}")
            lines += headers.map { $0.key.lowercased() == "host" ? "\treq.Host = \(q($0.value))" : "\treq.Header.Set(\(q($0.key)), \(q($0.value)))" }
            lines.append("\tclient := &http.Client{Timeout: \(timeout) * time.Second}")
            if !model.followRedirects { lines.append("\tclient.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }") }
            lines.append("\tres, err := client.Do(req)\n\tif err != nil {\n\t\tpanic(err)\n\t}\n\tdefer res.Body.Close()\n\tdata, _ := io.ReadAll(res.Body)\n\tfmt.Println(res.StatusCode)\n\tfmt.Println(string(data))\n}")
            return "package main\n\nimport (\n" + imports.sorted().map { "\t\"\($0)\"" }.joined(separator: "\n") + "\n)\n\n" + lines.joined(separator: "\n") + "\n"
        case .java:
            let restricted: Set<String> = ["connection", "content-length", "expect", "host", "upgrade"]
            let publisher = text.map { "HttpRequest.BodyPublishers.ofString(\(q($0)))" } ?? base64.map { "HttpRequest.BodyPublishers.ofByteArray(Base64.getDecoder().decode(\(q($0))))" } ?? "HttpRequest.BodyPublishers.noBody()"
            let headerCode = headers.filter { !restricted.contains($0.key.lowercased()) }.map { "            .header(\(q($0.key)), \(q($0.value)))\n" }.joined()
            return "import java.net.URI;\nimport java.net.http.HttpClient;\nimport java.net.http.HttpRequest;\nimport java.net.http.HttpResponse;\nimport java.time.Duration;\nimport java.util.Base64;\n\npublic class Main {\n    public static void main(String[] args) throws Exception {\n        HttpClient client = HttpClient.newBuilder()\n            .followRedirects(HttpClient.Redirect.\(model.followRedirects ? "NORMAL" : "NEVER"))\n            .build();\n        HttpRequest request = HttpRequest.newBuilder()\n            .uri(URI.create(\(url)))\n            .timeout(Duration.ofSeconds(\(timeout)))\n\(headerCode)            .method(\(method), \(publisher))\n            .build();\n        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());\n        System.out.println(response.statusCode());\n        System.out.println(response.body());\n    }\n}\n"
        case .csharp:
            var lines = ["using System;", "using System.Net.Http;", "", "var handler = new HttpClientHandler { AllowAutoRedirect = \(model.followRedirects) };", "using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(\(timeout)) };", "using var request = new HttpRequestMessage(new HttpMethod(\(method)), \(url));"]
            if let content = text.map({ "new StringContent(\(q($0)))" }) ?? base64.map({ "new ByteArrayContent(Convert.FromBase64String(\(q($0))))" }) { lines += ["request.Content = \(content);", "request.Content.Headers.Clear();"] }
            for (key, value) in headers where key.lowercased() != "content-length" {
                lines.append((body != nil && key.lowercased().hasPrefix("content-") ? "request.Content.Headers" : "request.Headers") + ".TryAddWithoutValidation(\(q(key)), \(q(value)));")
            }
            lines += ["var response = await client.SendAsync(request);", "Console.WriteLine((int)response.StatusCode);", "Console.WriteLine(await response.Content.ReadAsStringAsync());"]
            return lines.joined(separator: "\n") + "\n"
        case .php:
            func p(_ value: String) -> String { single(value, escapingBackslash: true) }
            var options = ["    CURLOPT_URL => \(p(rawURL))", "    CURLOPT_CUSTOMREQUEST => \(p(rawMethod))", "    CURLOPT_RETURNTRANSFER => true", "    CURLOPT_FOLLOWLOCATION => \(model.followRedirects)", "    CURLOPT_TIMEOUT => \(timeout)",
                           "    CURLOPT_HTTPHEADER => [\n" + headers.map { "        \(p($0.key + ": " + $0.value))," }.joined(separator: "\n") + "\n    ]"]
            if let text { options.append("    CURLOPT_POSTFIELDS => \(p(text))") }
            if let base64 { options.append("    CURLOPT_POSTFIELDS => base64_decode(\(p(base64)))") }
            return "<?php\n$curl = curl_init();\ncurl_setopt_array($curl, [\n" + options.joined(separator: ",\n") + ",\n]);\n$response = curl_exec($curl);\necho curl_getinfo($curl, CURLINFO_RESPONSE_CODE), PHP_EOL, $response, PHP_EOL;\ncurl_close($curl);\n"
        case .ruby:
            func r(_ value: String) -> String { q(value).replacingOccurrences(of: "#", with: "\\#") }
            var lines = ["require 'net/http'", "require 'uri'", ""]
            if model.followRedirects { lines.append("# Net::HTTP does not follow redirects; check response['location'] to continue.") }
            lines += ["uri = URI(\(r(rawURL)))", "request = Net::HTTPGenericRequest.new(\(r(rawMethod)), \(body != nil), \(rawMethod != "HEAD"), uri.request_uri)"]
            lines += headers.map { "request[\(r($0.key))] = \(r($0.value))" }
            if let text { lines.append("request.body = \(r(text))") }
            if let base64 { lines.append("request.body = \(r(base64)).unpack1('m')") }
            lines += ["response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: \(timeout), read_timeout: \(timeout)) { |http| http.request(request) }", "puts response.code", "puts response.body"]
            return lines.joined(separator: "\n") + "\n"
        case .httpie:
            var parts = ["http"]
            if model.followRedirects { parts.append("--follow") }
            parts.append("--timeout=\(timeout)")
            if let text { parts.append("--raw \(sh(text))") }
            parts += [sh(rawMethod), sh(rawURL)] + headers.map { sh($0.value.isEmpty ? $0.key + ";" : $0.key + ":" + $0.value) }
            return (base64.map { "printf %s \(sh($0)) | base64 --decode | " } ?? "") + parts.joined(separator: " \\\n  ") + "\n"
        case .powershell:
            func s(_ value: String) -> String { single(value, escapingBackslash: false) }
            let contentType = headers.first { $0.key.lowercased() == "content-type" }?.value
            var lines = ["$headers = @{"] + headers.filter { $0.key.lowercased() != "content-type" }.map { "    \(s($0.key)) = \(s($0.value))" } + ["}"]
            var call = "$response = Invoke-WebRequest -UseBasicParsing -Uri \(s(rawURL)) -Method \(s(rawMethod)) -Headers $headers -TimeoutSec \(timeout)"
            if !model.followRedirects { call += " -MaximumRedirection 0" }
            if let contentType { call += " -ContentType \(s(contentType))" }
            if let text { call += " -Body \(s(text))" }
            if let base64 { call += " -Body ([Convert]::FromBase64String(\(s(base64))))" }
            lines += [call, "$response.StatusCode", "$response.Content"]
            return lines.joined(separator: "\n") + "\n"
        case .swift:
            let headerCode = headers.map { "request.setValue(\(q($0.value)), forHTTPHeaderField: \(q($0.key)))" }.joined(separator: "\n")
            let bodyCode = text.map { "request.httpBody = Data(\(q($0)).utf8)\n" } ?? base64.map { "request.httpBody = Data(base64Encoded: \(q($0)))\n" } ?? ""
            return "import Foundation\n\nvar request = URLRequest(url: URL(string: \(url))!)\nrequest.httpMethod = \(method)\nrequest.timeoutInterval = \(model.timeout)\n\(headerCode)\n" + bodyCode + "\nlet (data, response) = try await URLSession.shared.data(for: request)\nprint((response as? HTTPURLResponse)?.statusCode ?? 0)\nprint(String(decoding: data, as: UTF8.self))\n"
        case .javascript:
            let headerCode = headers.map { "    \(q($0.key)): \(q($0.value))" }.joined(separator: ",\n")
            let bodyCode = text.map { ",\n  body: \(q($0))" } ?? base64.map { ",\n  body: Uint8Array.from(atob(\(q($0))), c => c.charCodeAt(0))" } ?? ""
            return "const response = await fetch(\(url), {\n  method: \(method),\n  redirect: \(q(model.followRedirects ? "follow" : "manual")),\n  signal: AbortSignal.timeout(\(Int(model.timeout * 1000))),\n  headers: {\n\(headerCode)\n  }" + bodyCode + "\n});\nconsole.log(response.status, await response.text());\n"
        case .python:
            let headerCode = headers.map { "    \(q($0.key)): \(q($0.value))" }.joined(separator: ",\n")
            let bodyCode = text.map { ",\n    data=\(q($0)).encode()" } ?? base64.map { ",\n    data=base64.b64decode(\(q($0)))" } ?? ""
            return "import requests\n" + (base64 == nil ? "" : "import base64\n") + "\nresponse = requests.request(\n    \(method), \(url),\n    headers={\n\(headerCode)\n    },\n    timeout=\(timeout),\n    allow_redirects=\(model.followRedirects ? "True" : "False")" + bodyCode + "\n)\nprint(response.status_code)\nprint(response.text)\n"
        case .kotlin:
            func kq(_ value: String) -> String { q(value).replacingOccurrences(of: "$", with: "\\$") }
            let headerCode = headers.map { "    .addHeader(\(kq($0.key)), \(kq($0.value)))" }.joined(separator: "\n")
            let bodyCode = text.map { "\(kq($0)).toRequestBody()" } ?? base64.map { "Base64.getDecoder().decode(\(kq($0))).toRequestBody()" } ?? (["POST", "PUT", "PATCH"].contains(rawMethod) ? "ByteArray(0).toRequestBody()" : "null")
            return "// Requires OkHttp 4.x or newer.\nimport okhttp3.*\nimport okhttp3.RequestBody.Companion.toRequestBody\nimport java.util.Base64\nimport java.util.concurrent.TimeUnit\n\nval client = OkHttpClient.Builder()\n    .callTimeout(\(Int(model.timeout)), TimeUnit.SECONDS)\n    .followRedirects(\(model.followRedirects))\n    .build()\nval request = Request.Builder()\n    .url(\(kq(request.url!.absoluteString)))\n\(headerCode)\n    .method(\(method), \(bodyCode))\n    .build()\nclient.newCall(request).execute().use { response ->\n    println(response.code)\n    println(response.body?.string())\n}\n"
        }
    }
}

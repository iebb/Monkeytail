import XCTest
@testable import MonkeytailCore

final class CoreTests: XCTestCase {
    func testBrowserCurlRoundTrips() throws {
        for profile in BrowserProfile.allCases {
            for browserHeaders in [true, false] {
                var request = APIRequest(url: "https://example.com")
                request.impersonation = BrowserImpersonation(profile: profile, browserHeaders: browserHeaders)
                request.headers = [Field("User-Agent", "My debug agent")]
                let command = try CurlCodec.encode(request)
                XCTAssertTrue(command.hasPrefix("curl-impersonate "))
                let decoded = try CurlCodec.decode(command).request
                XCTAssertEqual(decoded.impersonation, request.impersonation)
                XCTAssertEqual(decoded.headers.first?.value, "My debug agent")
            }
        }
    }

    func testBrowserCurlImportsAndValidation() throws {
        XCTAssertEqual(try CurlCodec.decode("curl --impersonate chrome:no https://example.com").request.impersonation, BrowserImpersonation(profile: .chrome, browserHeaders: false))
        XCTAssertEqual(try CurlCodec.decode("/usr/local/bin/curl_safari260_ios https://example.com").request.impersonation?.profile, .safariIOS)
        XCTAssertNil(try CurlCodec.decode("curl https://example.com -A 'Chrome'").request.impersonation)
        for target in ["unknown", "chrome:maybe", "chrome:", "chrome:no:yes"] {
            XCTAssertThrowsError(try CurlCodec.decode("curl --impersonate '\(target)' https://example.com"))
        }
    }

    func testOldWorkspacesDecodeWithSystemTransport() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(APIRequest())) as! [String: Any]
        object.removeValue(forKey: "impersonation")
        let request = try JSONDecoder().decode(APIRequest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(request.impersonation)
        XCTAssertTrue(try CurlCodec.encode(request).hasPrefix("curl "))
    }

    func testBrowserProfilesSurviveCollectionRoundTrips() throws {
        var workspace = Workspace.starter
        workspace.collections[0].requests[0].impersonation = BrowserImpersonation(profile: .safariIOS, browserHeaders: false)
        for format in ExportFormat.allCases {
            let decoded = try CollectionCodec.decode(CollectionCodec.encode(workspace, format: format)).workspace
            XCTAssertEqual(decoded.collections[0].requests[0].impersonation, workspace.collections[0].requests[0].impersonation)
            XCTAssertNil(decoded.collections[0].requests[1].impersonation)
        }
    }

    func testCurlQuotedMultilineAndHeaders() throws {
        let result = try CurlCodec.decode("""
        curl 'https://example.com/api?x=1&y=2' \\
          -H 'X-Name: a: b' \\
          --json '{"title":"hello world"}'
        """)
        XCTAssertEqual(result.request.method, "POST")
        XCTAssertEqual(result.request.url, "https://example.com/api?x=1&y=2")
        XCTAssertEqual(result.request.headers.first?.value, "a: b")
        XCTAssertEqual(result.request.bodyKind, .json)
        XCTAssertEqual(result.request.body, #"{"title":"hello world"}"#)
    }

    func testCurlQuoteRoundTrip() throws {
        var model = APIRequest(url: "https://example.com")
        model.method = "POST"; model.bodyKind = .text; model.body = "It's a $value\nwith \"quotes\" and `ticks`"
        model.headers = [Field("X-Note", "a'b")]
        let parsed = try CurlCodec.decode(CurlCodec.encode(model))
        XCTAssertEqual(parsed.request.body, model.body)
        XCTAssertEqual(parsed.request.headers.first { $0.name == "X-Note" }?.value, "a'b")
        XCTAssertTrue(parsed.request.followRedirects)
    }

    func testCurlAttachedArgumentsAndBasicAuth() throws {
        let result = try CurlCodec.decode("curl -XPUT -H'X-Key: value' --url=https://example.com -u 'alice:a:b' --max-time 15")
        XCTAssertEqual(result.request.method, "PUT")
        XCTAssertEqual(result.request.auth.password, "a:b")
        XCTAssertEqual(result.request.timeout, 15)
    }

    func testCurlGetEncoding() throws {
        let result = try CurlCodec.decode("curl -G 'https://example.com/search' --data-urlencode 'q=a+b & c'")
        XCTAssertEqual(result.request.method, "GET")
        XCTAssertEqual(result.request.url, "https://example.com/search?q=a%2Bb%20%26%20c")
        XCTAssertEqual(result.request.bodyKind, .none)
    }

    func testCurlHeadAndProxy() throws {
        let result = try CurlCodec.decode("curl -I https://example.com --proxy socks5h://alice:pass@localhost:1080")
        XCTAssertEqual(result.request.method, "HEAD")
        XCTAssertEqual(result.proxy?.kind, .socks)
        XCTAssertEqual(result.proxy?.username, "alice")
    }

    func testCurlRejectsDangerousOrUnsupportedSyntax() {
        for source in ["curl https://example.com | sh", "curl $(whoami)", "curl 'unterminated", "curl https://example.com --data-urlencode @secret", "curl https://example.com --unknown foo", "curl https://a.example https://b.example", "curl https://example.com -H"] {
            XCTAssertThrowsError(try CurlCodec.decode(source), source)
        }
    }

    func testCurlRawAtSignAndExplicitMethod() throws {
        let request = try CurlCodec.decode("curl https://example.com -X DELETE --data-raw '@literal'").request
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.body, "@literal")
    }

    func testVariableResolution() throws {
        XCTAssertEqual(try RequestBuilder.resolve("{{ base_url }}/{{id}}", variables: ["base_url": "https://{{host}}", "host": "example.com", "id": "42"]), "https://example.com/42")
        XCTAssertThrowsError(try RequestBuilder.resolve("{{missing}}", variables: [:]))
        XCTAssertThrowsError(try RequestBuilder.resolve("{{a}}", variables: ["a": "{{b}}", "b": "{{a}} "]))
    }

    func testRequestPreservesRepeatedQueryAndFiltersDisabled() throws {
        var model = APIRequest(url: "https://example.com?tag=one")
        model.query = [Field("tag", "two"), Field("q", "a+b & c"), Field("skip", "yes", enabled: false)]
        model.headers = [Field("X-Env", "{{name}}"), Field("Skip", "yes", enabled: false)]
        let request = try RequestBuilder.build(model, variables: ["name": "dev"])
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.map(\.name), ["tag", "tag", "q"])
        XCTAssertEqual(items.last?.value, "a+b & c")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Env"), "dev")
        XCTAssertNil(request.value(forHTTPHeaderField: "Skip"))
    }

    func testFormEscapesReservedCharacters() throws {
        var model = APIRequest(method: "POST", url: "https://example.com")
        model.bodyKind = .form; model.form = [Field("name", "a+b & c"), Field("name", "two")]
        let request = try RequestBuilder.build(model)
        XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "name=a%2Bb%20%26%20c&name=two")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
    }

    func testBearerOverridesHeader() throws {
        var model = APIRequest(url: "https://example.com")
        model.headers = [Field("Authorization", "old")]
        model.auth.kind = .bearer; model.auth.token = "{{token}}"
        XCTAssertEqual(try RequestBuilder.build(model, variables: ["token": "new"]).value(forHTTPHeaderField: "Authorization"), "Bearer new")
    }

    func testInvalidRequestFailsBeforeNetwork() {
        var model = APIRequest(url: "file:///tmp/file")
        XCTAssertThrowsError(try RequestBuilder.build(model))
        model.url = "https://example.com"; model.headers = [Field("Bad Header", "foo")]
        XCTAssertThrowsError(try RequestBuilder.build(model))
        model.headers = [Field("X-Good", "one\r\nInjected: yes")]
        XCTAssertThrowsError(try RequestBuilder.build(model))
        model.headers = []; model.bodyKind = .json; model.body = "{broken}"
        XCTAssertThrowsError(try RequestBuilder.build(model))
    }

    func testJSONFormatFragmentsAndTree() throws {
        XCTAssertEqual(try JSONTools.format("true"), "true")
        XCTAssertEqual(try JSONTools.format("{\"z\":2,\"a\":true}", pretty: false), "{\"a\":true,\"z\":2}")
        let tree = try JSONTools.tree("{\"one\":1,\"yes\":true,\"nil\":null,\"items\":[\"hello\"]}")
        XCTAssertEqual(tree.children?.first { $0.key == "one" }?.kind, "number")
        XCTAssertEqual(tree.children?.first { $0.key == "yes" }?.summary, "true")
        XCTAssertEqual(tree.children?.first { $0.key == "items" }?.children?.first?.summary, "\"hello\"")
    }

    func testNativeRoundTrip() throws {
        let original = Workspace.starter
        let decoded = try CollectionCodec.decode(CollectionCodec.encode(original, format: .native))
        XCTAssertEqual(decoded.workspace, original)
    }

    func testThirdPartyRoundTrips() throws {
        var workspace = Workspace.starter
        workspace.collections[0].requests[0].query = [Field("q", "a+b"), Field("disabled", "x", enabled: false)]
        workspace.collections[0].requests[0].auth.kind = .bearer
        workspace.collections[0].requests[0].auth.token = "{{token}}"
        for format in [ExportFormat.postman, .insomnia] {
            let decoded = try CollectionCodec.decode(CollectionCodec.encode(workspace, format: format)).workspace
            let requests = decoded.collections.flatMap(\.requests)
            XCTAssertEqual(requests.count, 3)
            XCTAssertEqual(requests[0].url, "{{base_url}}/get")
            XCTAssertEqual(requests[0].query.map(\.value), ["a+b", "x"])
            XCTAssertFalse(requests[0].query[1].enabled)
            XCTAssertEqual(requests[0].auth.token, "{{token}}")
            XCTAssertEqual(requests[1].body, workspace.collections[0].requests[1].body)
            XCTAssertFalse(requests[1].scriptsEnabled)
        }
    }

    func testPostmanNestedAuthAndEvents() throws {
        let source = #"""
        {"info":{"name":"Demo"},"auth":{"type":"bearer","bearer":[{"key":"token","value":"abc"}]},"event":[{"listen":"prerequest","script":{"exec":["console.log('root')"]}}],"item":[{"name":"Users","item":[{"name":"List","request":{"method":"GET","url":{"raw":"https://example.com?x=1","query":[{"key":"x","value":"1"},{"key":"skip","value":"2","disabled":true}]}}}]}]}
        """#
        let result = try CollectionCodec.decode(Data(source.utf8))
        let request = result.workspace.collections[0].requests[0]
        XCTAssertEqual(request.name, "List")
        XCTAssertEqual(result.workspace.collections[0].folders?.first?.name, "Users")
        var collection = result.workspace.collections[0]; collection.defaults?.scriptsEnabled = true
        let resolved = try RequestInheritance.resolve(request, collection: collection, environment: [:])
        XCTAssertEqual(resolved.request.auth.token, "abc")
        XCTAssertEqual(request.url, "https://example.com")
        XCTAssertEqual(request.query.count, 2)
        XCTAssertTrue(resolved.request.preScript.contains("root"))
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testInsomniaEnvironmentSyntax() throws {
        let source = #"{"__export_format":4,"resources":[{"_type":"request","name":"List","url":"{{ _.base_url }}/v1","method":"GET","headers":[{"name":"X-Value","value":"{{ _.token }}"}]},{"_type":"environment","name":"Local","data":{"base_url":"https://example.com","count":42}}]}"#
        let result = try CollectionCodec.decode(Data(source.utf8)).workspace
        XCTAssertEqual(result.collections[0].requests[0].url, "{{base_url}}/v1")
        XCTAssertEqual(result.collections[0].requests[0].headers[0].value, "{{token}}")
        XCTAssertEqual(result.environments[0].values["count"], "42")
    }

    func testPostmanEnvironmentImport() throws {
        let source = #"{"name":"Staging","values":[{"key":"token","value":"secret","enabled":false},{"key":"base_url","value":"https://example.com","enabled":true}]}"#
        let result = try CollectionCodec.decode(Data(source.utf8)).workspace
        XCTAssertNil(result.environments[0].values["token"])
        XCTAssertEqual(result.environments[0].values["base_url"], "https://example.com")
    }

    func testProxyValidationAndNoFailover() throws {
        var proxy = ProxySettings(); proxy.kind = .http; proxy.host = "localhost"; proxy.port = "99999"
        XCTAssertThrowsError(try HTTPClient.configuration(proxy: proxy, timeout: 30))
        proxy.port = "8080"
        let config = try HTTPClient.configuration(proxy: proxy, timeout: 30)
        XCTAssertEqual(config.proxyConfigurations.count, 1)
        XCTAssertFalse(config.proxyConfigurations[0].allowFailover)
    }
}

final class ByteFormatterTests: XCTestCase {
    func testBinaryAndHexPreserveOffsetsAndNonPrintableBytes() {
        let bytes: [UInt8] = [0, 65, 127, 255, 32]
        XCTAssertEqual(ByteFormatter.dump(bytes, width: 4), "00000000  00 41 7F FF  .A..\n00000004  20            ")
        XCTAssertEqual(ByteFormatter.dump([0, 255], width: 2, binary: true), "00000000  00000000 11111111  ..")
        XCTAssertEqual(ByteFormatter.dump([]), "")
    }
}

import XCTest
@testable import MonkeytailCore

final class AdvancedFeatureTests: XCTestCase {
    func testNestedDefaultsOverrideAndDisabledHeadersSuppressParents() throws {
        var root = RequestDefaults(); root.headers = [Field("X-Mode", "root"), Field("X-Remove", "root")]; root.variables = [Field("host", "root")]; root.auth.kind = .bearer; root.auth.token = "root-token"; root.scriptsEnabled = true; root.preScript = "root();"
        var parent = RequestFolder(name: "Parent"); parent.defaults.variables = [Field("host", "folder")]; parent.defaults.preScript = "disabled();"; parent.defaults.scriptsEnabled = false
        var child = RequestFolder(name: "Child", parentID: parent.id); child.defaults.headers = [Field("x-mode", "child")]; child.defaults.scriptsEnabled = true; child.defaults.preScript = "child();"
        var request = APIRequest(url: "https://{{host}}"); request.folderID = child.id; request.auth.kind = .inherit; request.headers = [Field("X-Remove", "", enabled: false)]; request.variables = [Field("host", "request.test")]
        var collection = RequestCollection(name: "API", requests: [request]); collection.defaults = root; collection.folders = [parent, child]
        let value = try RequestInheritance.resolve(request, collection: collection, environment: ["host": "environment"])
        let built = try RequestBuilder.build(value.request, variables: value.variables)
        XCTAssertEqual(built.url?.host, "request.test"); XCTAssertEqual(built.value(forHTTPHeaderField: "X-Mode"), "child"); XCTAssertNil(built.value(forHTTPHeaderField: "X-Remove")); XCTAssertEqual(built.value(forHTTPHeaderField: "Authorization"), "Bearer root-token")
        XCTAssertEqual(value.request.preScript, "root();\nchild();")
        parent.parentID = child.id; collection.folders = [parent, child]
        XCTAssertThrowsError(try RequestInheritance.resolve(request, collection: collection, environment: [:]))
    }

    func testPostmanHierarchyAndAdvancedMetadataRoundTrip() throws {
        var folder = RequestFolder(name: "Accounts"); folder.defaults.headers = [Field("X-Tenant", "42")]; folder.defaults.auth.kind = .apiKey; var key = APIKeyAuth(); key.value = "key-value"; folder.defaults.auth.apiKey = key
        let nested = RequestFolder(name: "Nested", parentID: folder.id)
        var request = APIRequest(name: "Query", method: "POST", url: "https://example.test/graphql"); request.folderID = nested.id; request.auth.kind = .inherit; request.transport = .graphql; request.graphql = GraphQLRequest(); request.cookieJarEnabled = true; request.assertions = [ResponseAssertion()]; request.mock = MockResponse()
        var collection = RequestCollection(name: "API", requests: [request]); collection.folders = [folder, nested]
        let imported = try CollectionCodec.decode(CollectionCodec.encode(Workspace(collections: [collection]), format: .postman)).workspace
        let decoded = try XCTUnwrap(imported.collections.first?.requests.first)
        let c = try XCTUnwrap(imported.collections.first)
        XCTAssertEqual(decoded.name, "Query"); XCTAssertEqual(decoded.transport, .graphql); XCTAssertEqual(decoded.graphql, request.graphql); XCTAssertEqual(decoded.assertions, request.assertions); XCTAssertEqual(decoded.cookieJarEnabled, true)
        let resolved = try RequestInheritance.resolve(decoded, collection: c, environment: [:])
        XCTAssertEqual(resolved.request.auth.apiKey?.value, "key-value"); XCTAssertEqual(resolved.request.headers.first?.value, "42")
        XCTAssertEqual(c.folders?.first(where: { $0.id == decoded.folderID })?.name, "Nested")
    }

    func testPKCEOfficialVectorCallbackStateAndRefreshRotation() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(OAuthFlow.challenge(verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        var config = OAuthConfiguration(); config.authorizationURL = "https://example.test/auth?state=old"; config.tokenURL = "https://example.test/token"; config.clientID = "client"; config.refreshToken = "refresh-old"
        let auth = try OAuthFlow.authorizationURL(config, state: "state", verifier: verifier)
        XCTAssertEqual(URLComponents(url: auth, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "state" }.count, 1)
        XCTAssertEqual(try OAuthFlow.code(from: URL(string: "monkeytail://oauth?state=state&code=abc")!, config: config, state: "state"), "abc")
        for callback in ["monkeytail://other?state=state&code=abc", "monkeytail://oauth?state=wrong&code=abc", "monkeytail://oauth?state=state&state=state&code=abc"] { XCTAssertThrowsError(try OAuthFlow.code(from: URL(string: callback)!, config: config, state: "state")) }
        let request = try OAuthFlow.tokenRequest(config, refresh: true)
        XCTAssertTrue(String(decoding: request.httpBody!, as: UTF8.self).contains("grant_type=refresh_token"))
        let now = Date(timeIntervalSince1970: 1000)
        let response = APIResponse(status: 200, headers: [], body: Data(#"{"access_token":"access-new","refresh_token":"refresh-new","expires_in":3600,"token_type":"Bearer"}"#.utf8), duration: 0, url: config.tokenURL)
        let updated = try OAuthFlow.apply(response, to: config, now: now)
        XCTAssertEqual(updated.refreshToken, "refresh-new"); XCTAssertEqual(updated.expiresAt, now.addingTimeInterval(3600))
    }

    func testAWSS3PublishedSignatureVectors() throws {
        var credentials = AWSAuth(); credentials.accessKey = "AKIAIOSFODNN7EXAMPLE"; credentials.secretKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"; credentials.service = "s3"
        let date = ISO8601DateFormatter().date(from: "2013-05-24T00:00:00Z")!
        var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!); request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        let signed = try AWSSigner.sign(request, credentials: credentials, date: date)
        XCTAssertTrue(signed.value(forHTTPHeaderField: "Authorization")!.hasSuffix("Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41"))
        request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/?prefix=J&max-keys=2")!)
        XCTAssertTrue(try AWSSigner.sign(request, credentials: credentials, date: date).value(forHTTPHeaderField: "Authorization")!.hasSuffix("Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7"))
    }

    func testCookieDomainPathExpiryPrefixesAndPublicSuffix() throws {
        var jar = CookieJar(); let now = Date(timeIntervalSince1970: 1000)
        jar.capture(headers: [Field("Set-Cookie", "session=abc; Secure; HttpOnly; Path=/api; Max-Age=60, other=ok; Domain=example.co.uk; Path=/"), Field("Set-Cookie", "bad=leak; Domain=co.uk"), Field("Set-Cookie", "evil=leak; Domain=other.test"), Field("Set-Cookie", "__Host-bad=leak; Secure; Domain=example.co.uk"), Field("Set-Cookie", "empty=ok;;")], url: URL(string: "https://api.example.co.uk/api/login")!, now: now)
        XCTAssertEqual(jar.cookies.count, 3)
        XCTAssertTrue(jar.header(for: URL(string: "https://api.example.co.uk/api/user")!, now: now).contains("session=abc"))
        XCTAssertFalse(jar.header(for: URL(string: "http://api.example.co.uk/api/user")!, now: now).contains("session="))
        XCTAssertFalse(jar.header(for: URL(string: "https://api.example.co.uk/apix")!, now: now).contains("session="))
        XCTAssertEqual(jar.header(for: URL(string: "https://www.example.co.uk/")!, now: now), "other=ok")
        XCTAssertFalse(jar.header(for: URL(string: "https://api.example.co.uk/api/user")!, now: now.addingTimeInterval(61)).contains("session="))
        XCTAssertThrowsError(try StoredCookie(name: "bad\r\n", value: "x", domain: "example.test").validated())
        XCTAssertThrowsError(try StoredCookie(name: "bad", value: "x", domain: "github.io", hostOnly: false).validated())
    }

    func testOpenAPIYAMLParametersExamplesAndSchemaReferences() throws {
        let yaml = """
        openapi: 3.1.0
        info: {title: Sample, version: '1'}
        servers: [{url: 'https://example.test'}]
        components:
          schemas:
            Payload: {type: object, required: [id], properties: {id: {type: integer}}}
        paths:
          /items/{id}:
            parameters: [{name: id, in: path, required: true, schema: {type: integer}}]
            post:
              tags: [Items]
              summary: Update item
              requestBody:
                content:
                  application/json:
                    schema: {$ref: '#/components/schemas/Payload'}
                    example: {id: 42}
              responses:
                '200': {description: OK, content: {application/json: {schema: {$ref: '#/components/schemas/Payload'}}}}
        """
        let workspace = try OpenAPICodec.decode(Data(yaml.utf8)).workspace
        let request = try XCTUnwrap(workspace.collections.first?.requests.first)
        let effective = try RequestInheritance.resolve(request, collection: workspace.collections.first, environment: workspace.environments.first!.values)
        XCTAssertEqual(try RequestBuilder.build(effective.request, variables: effective.variables).url?.absoluteString, "https://example.test/items/1")
        XCTAssertEqual(request.parameterHints?.first?.required, true); XCTAssertNotNil(request.folderID)
        XCTAssertTrue(try JSONSchema.validate(Data(#"{"id":42}"#.utf8), schema: request.responseSchema!).isEmpty)
        XCTAssertFalse(try JSONSchema.validate(Data(#"{"id":"wrong"}"#.utf8), schema: request.responseSchema!).isEmpty)
    }

    func testSchemaTypeCompositionAndInvalidPatterns() throws {
        let schema = #"{"type":"object","required":["id"],"properties":{"id":{"type":"integer","minimum":1},"name":{"type":["string","null"]}},"additionalProperties":false}"#
        XCTAssertTrue(try JSONSchema.validate(Data(#"{"id":2,"name":null}"#.utf8), schema: schema).isEmpty)
        XCTAssertFalse(try JSONSchema.validate(Data(#"{"id":true,"extra":1}"#.utf8), schema: schema).isEmpty)
        XCTAssertFalse(try JSONSchema.validate(Data("2".utf8), schema: #"{"oneOf":[{"type":"number"},{"type":"integer"}]}"#).isEmpty)
        XCTAssertThrowsError(try JSONSchema.validate(Data(#""aaaa""#.utf8), schema: #"{"pattern":"(a+)+$"}"#))
        XCTAssertThrowsError(try JSONSchema.validate(Data("{}".utf8), schema: #"{"$ref":"https://example.test/schema"}"#))
    }

    func testGraphQLBodyAndIntrospectionUnwrap() throws {
        var request = APIRequest(method: "POST", url: "https://example.test/graphql"); request.transport = .graphql
        var graph = GraphQLRequest(); graph.query = "query Find($id: Int!) { item(id: $id) { id } }"; graph.operationName = "Find"; graph.variables = #"{"id":{{id}}}"#; request.graphql = graph
        let built = try RequestBuilder.build(request, variables: ["id": "7"])
        let body = try JSONSerialization.jsonObject(with: built.httpBody!) as! [String: Any]
        XCTAssertEqual(body["operationName"] as? String, "Find"); XCTAssertEqual((body["variables"] as? [String: Any])?["id"] as? Int, 7)
        graph.variables = "[]"; XCTAssertThrowsError(try graph.body(values: [:]))
        let schema = #"{"data":{"__schema":{"types":[{"name":"Query","fields":[{"name":"item","args":[{"name":"id"}],"type":{"kind":"NON_NULL","ofType":{"name":"Item","kind":"OBJECT"}}}]}]}}}"#
        let fields = try GraphQLSchema.fields(Data(schema.utf8)); XCTAssertEqual(fields.first?.id, "Query.item"); XCTAssertEqual(fields.first?.composite, true)
    }

    func testSSEMultilineIDsCommentsAndBounds() throws {
        var parser = SSEParser()
        XCTAssertNil(try parser.consume(": heartbeat")); XCTAssertNil(try parser.consume("id: 12")); XCTAssertNil(try parser.consume("event: update")); XCTAssertNil(try parser.consume("retry: 1500")); XCTAssertNil(try parser.consume("data: first")); XCTAssertNil(try parser.consume("data: second"))
        let event = try XCTUnwrap(parser.consume("")); XCTAssertEqual(event.text, "first\nsecond"); XCTAssertEqual(event.type, "update"); XCTAssertEqual(parser.lastEventID, "12"); XCTAssertEqual(parser.retryMilliseconds, 1500)
        XCTAssertNil(try parser.consume("id:")); XCTAssertNil(try parser.consume("")); XCTAssertEqual(parser.lastEventID, "")
        XCTAssertThrowsError(try parser.consume(String(repeating: "x", count: 65537)))
    }

    func testAssertionsDistinguishMissingJSONAndCanonicalObjects() {
        let response = APIResponse(status: 201, headers: [Field("X-ID", "42")], body: Data(#"{"value":{"b":2,"a":1}}"#.utf8), duration: 0.1, url: "https://example.test")
        var status = ResponseAssertion(); status.expected = "201"
        var json = ResponseAssertion(); json.kind = .json; json.path = "$.value"; json.expected = #"{"a":1,"b":2}"#
        var missing = json; missing.id = UUID(); missing.path = "$.missing"
        var header = ResponseAssertion(); header.kind = .header; header.path = "x-id"; header.expected = "42"
        XCTAssertEqual(ResponseTests.evaluate([status, json, missing, header], response: response).map(\.passed), [true, true, false, true])
    }

    func testSyncRetainsDefinitionsAndNeverTransfersAdvancedCredentials() throws {
        var folder = RequestFolder(name: "Private"); folder.defaults.auth.kind = .aws; var aws = AWSAuth(); aws.accessKey = "access-private"; aws.secretKey = "secret-private"; folder.defaults.auth.aws = aws; folder.defaults.scriptsEnabled = true
        var request = APIRequest(url: "https://example.test"); request.folderID = folder.id; request.auth.kind = .oauth2; var oauth = OAuthConfiguration(); oauth.clientSecret = "client-private"; oauth.accessToken = "token-private"; oauth.refreshToken = "refresh-private"; request.auth.oauth = oauth; request.scriptsEnabled = false; request.postScript = "pm.test('x', () => {});"
        var collection = RequestCollection(name: "Shared", requests: [request]); collection.folders = [folder]
        let workspace = Workspace(collections: [collection]); var state = WorkspaceSyncState(); try state.capture(workspace)
        let encoded = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        for secret in ["access-private", "secret-private", "client-private", "token-private", "refresh-private"] { XCTAssertFalse(encoded.contains(secret)); for record in state.records { XCTAssertFalse(String(decoding: record.payload ?? Data(), as: UTF8.self).contains(secret)) } }
        let fresh = try state.workspace(local: Workspace()); XCTAssertEqual(fresh.collections.first?.folders?.first?.name, "Private"); XCTAssertEqual(fresh.collections.first?.folders?.first?.defaults.auth.aws?.secretKey, ""); XCTAssertEqual(fresh.collections.first?.requests.first?.auth.oauth?.accessToken, "")
        XCTAssertEqual(fresh.collections.first?.folders?.first?.defaults.scriptsEnabled, true); XCTAssertEqual(fresh.collections.first?.requests.first?.scriptsEnabled, false)
        let own = try state.workspace(local: workspace); XCTAssertEqual(own.collections.first?.requests.first?.auth.oauth?.accessToken, "token-private"); XCTAssertEqual(own.collections.first?.folders?.first?.defaults.scriptsEnabled, true)
    }

    func testCodeExportsRedactKnownCredentialsAndPreserveBinaryBody() throws {
        var request = APIRequest(method: "POST", url: "https://example.test?api_key=secret-query"); request.auth.kind = .bearer; request.auth.token = "secret-token"; request.headers = [Field("X-API-Key", "secret-header")]; request.bodyKind = .file; request.fileBody = RequestFile(filename: "bytes.bin", mimeType: "application/octet-stream", data: Data([0, 255, 13, 10]))
        for language in CodeLanguage.allCases {
            let code = try CodeGenerator.generate(request, variables: [:], language: language)
            for secret in ["secret-query", "secret-token", "secret-header"] { XCTAssertFalse(code.contains(secret)) }
            XCTAssertTrue(code.contains("AP8NCg==")); XCTAssertTrue(try CodeGenerator.generate(request, variables: [:], language: language, redact: false).contains("secret-query"))
        }
    }

    func testFormCodeExportAndCookieAndSSEEdgeCases() throws {
        var json = APIRequest(method: "POST", url: "https://example.test/items?q=1"); json.bodyKind = .json; json.body = ##"{"name":"it's \"#{1}\" $x \\ ok","price":5}"##
        json.headers = [Field("Content-Type", "application/json"), Field("X-Trace", "abc")]
        for language in CodeLanguage.allCases {
            let code = try CodeGenerator.generate(json, variables: [:], language: language)
            XCTAssertFalse(code.contains(Data(json.body.utf8).base64EncodedString()), language.rawValue)
            XCTAssertTrue(code.contains("X-Trace") && code.contains("example.test/items?q=1") && code.contains("price"), language.rawValue)
        }
        var request = APIRequest(method: "POST", url: "https://example.test"); request.bodyKind = .form
        request.form = [Field("password", "private-form"), Field("public", "visible")]
        let code = try CodeGenerator.generate(request, variables: [:], language: .swift)
        let privateBytes = Data("password=private-form&public=visible".utf8).base64EncodedString()
        XCTAssertFalse(code.contains(privateBytes))
        var jar = CookieJar()
        jar.capture(headers: [Field("Set-Cookie", "bad=parent; Domain=0.1"), Field("Set-Cookie", "finite=yes; Max-Age=NaN")], url: URL(string: "http://127.0.0.1/")!)
        XCTAssertEqual(jar.cookies.map(\.name), ["finite"]); XCTAssertNil(jar.cookies.first?.expires)
        var parser = SSEParser(); _ = try parser.consume("\u{feff}data: first"); _ = try parser.consume("retry: +123")
        XCTAssertNil(parser.retryMilliseconds); XCTAssertEqual(try parser.consume("")?.text, "first")
        let response = APIResponse(status: 200, headers: [], body: Data(), duration: 0.1, url: "https://example.test")
        var assertion = ResponseAssertion(); assertion.kind = .header; assertion.path = "Missing"; assertion.expected = ""
        XCTAssertEqual(ResponseTests.evaluate([assertion], response: response).first?.passed, false)
    }

    func testOfflineMockStatusErrorAndCancellation() async throws {
        var mock = MockResponse(); mock.status = 503; mock.body = #"{"error":"offline"}"#
        let response = try await mock.response(url: "https://example.test"); XCTAssertEqual(response.status, 503); XCTAssertEqual(response.diagnostics?.transport, "Offline mock")
        mock.simulatedError = "Connection failed"
        do { _ = try await mock.response(url: "https://example.test"); XCTFail("Expected error") } catch { XCTAssertEqual(error.localizedDescription, "Connection failed") }
        mock.simulatedError = nil; mock.delayMilliseconds = 30000
        let delayed = mock; let task = Task { try await delayed.response(url: "https://example.test") }; task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testSyncCanIncludeCredentialsAndPropagateTheirEdits() throws {
        var workspace = Workspace.starter
        workspace.collections[0].requests[0].auth.kind = .bearer
        workspace.collections[0].requests[0].auth.token = "first-token"
        workspace.collections[0].requests[0].headers.append(Field("X-API-Key", "first-key"))
        workspace.collections[0].requests[0].multipart = [MultipartPart(name: "api_key", value: "first-part")]
        workspace.environments[0].variables.append(Field("secret_value", "first-value"))
        var first = WorkspaceSyncState()
        try first.capture(workspace, includeCredentials: true)
        var remote = try first.workspace(local: workspace, includeCredentials: true)
        remote.collections[0].requests[0].auth.token = "new-token"
        let last = remote.collections[0].requests[0].headers.count - 1
        remote.collections[0].requests[0].headers[last].value = "new-key"
        remote.collections[0].requests[0].multipart![0].value = "new-part"
        var second = first
        try second.capture(remote, now: Date().addingTimeInterval(10), includeCredentials: true)
        first.merge(second)
        let merged = try first.workspace(local: workspace, includeCredentials: true)
        XCTAssertEqual(merged.collections[0].requests[0].auth.token, "new-token")
        XCTAssertEqual(merged.collections[0].requests[0].headers.last?.value, "new-key")
        XCTAssertEqual(merged.collections[0].requests[0].multipart?.first?.value, "new-part")
        try first.capture(merged, includeCredentials: false)
        let encoded = String(decoding: try JSONEncoder().encode(first), as: UTF8.self)
        // Record payloads are base64; inspect their decoded content too.
        let payloads = first.records.compactMap(\.payload).map { String(decoding: $0, as: UTF8.self) }.joined()
        XCTAssertFalse(payloads.contains("new-token")); XCTAssertFalse(payloads.contains("new-key")); XCTAssertFalse(payloads.contains("new-part"))
        XCTAssertFalse(encoded.isEmpty)
    }

}

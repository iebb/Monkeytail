import XCTest
@testable import MonkeytailCore

final class AuthAndGlobalsTests: XCTestCase {
    func testOAuth1MatchesTwitterSigningVectorAndRoundTripsThroughPostman() throws {
        var request = APIRequest(method: "POST", url: "https://api.twitter.com/1.1/statuses/update.json?include_entities=true"); request.headers = []
        request.bodyKind = .form; request.form = [Field("status", "Hello Ladies + Gentlemen, a signed OAuth request!")]
        var oauth1 = OAuth1Auth(); oauth1.consumerKey = "{{ck}}"; oauth1.consumerSecret = "kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw"
        oauth1.token = "370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb"; oauth1.tokenSecret = "LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE"
        request.auth.kind = .oauth1; request.auth.oauth1 = oauth1
        var built = try RequestBuilder.build(request, variables: ["ck": "xvz1evFS4wEEPTGEFPHBog"]); oauth1.consumerKey = "xvz1evFS4wEEPTGEFPHBog"
        XCTAssertTrue(built.value(forHTTPHeaderField: "Authorization")?.hasPrefix("OAuth oauth_consumer_key=\"xvz1evFS4wEEPTGEFPHBog\"") == true)
        built = try OAuth1Signer.sign(built, credentials: oauth1, nonce: "kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg", date: Date(timeIntervalSince1970: 1318622958))
        let header = try XCTUnwrap(built.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(header.contains(#"oauth_signature="hCtSmYh%2BiHYCEqBWrE7C7hYmtUk%3D""#), header)
        XCTAssertTrue(header.contains(#"oauth_token="370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb""#))
        var plain = oauth1; plain.signatureMethod = .plaintext; plain.realm = "Photos"
        let plaintext = try XCTUnwrap(OAuth1Signer.sign(built, credentials: plain).value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(plaintext.hasPrefix(#"OAuth realm="Photos", "#)); XCTAssertTrue(plaintext.contains(#"oauth_signature="kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw%26LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE""#))
        request.auth.oauth1 = plain
        let exported = try CollectionCodec.encode(Workspace(collections: [RequestCollection(name: "OAuth", requests: [request])]), format: .postman)
        let imported = try CollectionCodec.decode(exported)
        XCTAssertEqual(imported.workspace.collections[0].requests[0].auth.oauth1, plain); XCTAssertEqual(imported.warnings, [])
        var secrets: [String: String] = [:]
        let clean = SecretPolicy.strip(Workspace(collections: [RequestCollection(name: "OAuth", requests: [request])]), secrets: &secrets, files: false).collections[0].requests[0].auth.oauth1
        XCTAssertEqual([clean?.consumerSecret, clean?.token, clean?.tokenSecret], ["", "", ""]); XCTAssertEqual(clean?.consumerKey, "xvz1evFS4wEEPTGEFPHBog")
    }
    func testOAuth2PasswordGrantBuildsTokenRequestAndRoundTripsGrantThroughPostman() throws {
        var config = OAuthConfiguration(); config.grant = .password; config.tokenURL = "https://auth.example.com/token"; config.clientID = "app"; config.scope = "read"
        XCTAssertThrowsError(try OAuthFlow.tokenRequest(config))
        config.username = "ada"; config.password = "p&ss word"
        let body = try String(decoding: XCTUnwrap(OAuthFlow.tokenRequest(config).httpBody), as: UTF8.self)
        XCTAssertEqual(body, "client_id=app&grant_type=password&password=p%26ss%20word&scope=read&username=ada")
        var request = APIRequest(); request.auth.kind = .oauth2; request.auth.oauth = config
        let exported = try CollectionCodec.encode(Workspace(collections: [RequestCollection(name: "OAuth", requests: [request])]), format: .postman)
        let imported = try XCTUnwrap(CollectionCodec.decode(exported).workspace.collections.first?.requests.first?.auth.oauth)
        XCTAssertEqual(imported.grant, .password); XCTAssertEqual(imported.tokenURL, config.tokenURL); XCTAssertEqual(imported.username, "ada"); XCTAssertEqual(imported.scope, "read")
        var secrets: [String: String] = [:]
        let clean = SecretPolicy.strip(Workspace(collections: [RequestCollection(name: "OAuth", requests: [request])]), secrets: &secrets, files: false)
        XCTAssertEqual(clean.collections[0].requests[0].auth.oauth?.password, ""); XCTAssertEqual(SecretPolicy.restore(clean, secrets: secrets).collections[0].requests[0].auth.oauth?.password, "p&ss word")
    }
    func testDigestMatchesRFC2617AndRFC7616Vectors() throws {
        var rfc2617 = DigestChallenge(); rfc2617.realm = "testrealm@host.com"; rfc2617.nonce = "dcd98b7102dd2f0e8b11d0f600bfb0c093"; rfc2617.qop = ["auth", "auth-int"]; rfc2617.opaque = "5ccc069c403ebaf9f0171e9517f40e41"
        let legacy = try DigestAuth.authorization(rfc2617, username: "Mufasa", password: "Circle Of Life", method: "GET", uri: "/dir/index.html", cnonce: "0a4f113b")
        XCTAssertTrue(legacy.contains(#"response="6629fae49393a05397450978507c4ef1""#), legacy)
        XCTAssertTrue(legacy.contains("qop=auth, nc=00000001") && legacy.contains(#"opaque="5ccc069c403ebaf9f0171e9517f40e41""#))
        let header = #"Digest realm="http-auth@example.org", qop="auth, auth-int", algorithm=SHA-256, nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS""#
        var challenge = try XCTUnwrap(DigestAuth.challenge(from: [Field("Content-Type", "text/html"), Field("www-authenticate", header)]))
        XCTAssertEqual(challenge.qop, ["auth", "auth-int"]); XCTAssertEqual(challenge.algorithm, "SHA-256"); XCTAssertEqual(challenge.opaque, "FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS")
        let cnonce = "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"
        XCTAssertTrue(try DigestAuth.authorization(challenge, username: "Mufasa", password: "Circle of Life", method: "GET", uri: "/dir/index.html", cnonce: cnonce).contains("753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1"))
        challenge.algorithm = "MD5"
        XCTAssertTrue(try DigestAuth.authorization(challenge, username: "Mufasa", password: "Circle of Life", method: "GET", uri: "/dir/index.html", cnonce: cnonce).contains("8ca523f5e9506fed4657c9700eebdbec"))
        challenge.algorithm = "SHA-512-256"
        XCTAssertThrowsError(try DigestAuth.authorization(challenge, username: "a", password: "b", method: "GET", uri: "/"))
        XCTAssertNil(DigestAuth.parse(#"Basic realm="x""#))
        XCTAssertEqual(DigestAuth.uri(for: URL(string: "https://example.com/a%20b?x=1&y=2")!), "/a%20b?x=1&y=2")
        XCTAssertEqual(DigestAuth.uri(for: URL(string: "https://example.com")!), "/")
    }
    func testDigestRoundTripsThroughCurlPostmanAndInsomnia() throws {
        let imported = try CurlCodec.decode("curl --digest -u 'user:{{pass}}' https://example.com/private").request
        XCTAssertEqual(imported.auth.kind, .digest); XCTAssertEqual(imported.auth.password, "{{pass}}")
        let encoded = try CurlCodec.encode(imported, variables: ["pass": "secret"])
        XCTAssertTrue(encoded.contains("--digest --user 'user:secret'")); XCTAssertNil(try RequestBuilder.build(imported, variables: ["pass": "secret"]).value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try CurlCodec.decode(encoded).request.auth.kind, .digest)
        XCTAssertEqual(try CurlCodec.decode("curl -u a:b https://example.com").request.auth.kind, .basic)
        let workspace = Workspace(collections: [RequestCollection(name: "Digest", requests: [imported])])
        for format in [ExportFormat.postman, .insomnia] {
            let request = try XCTUnwrap(CollectionCodec.decode(CollectionCodec.encode(workspace, format: format)).workspace.collections.first?.requests.first)
            XCTAssertEqual(request.auth.kind, .digest, "\(format)"); XCTAssertEqual(request.auth.username, "user")
        }
    }
    func testGlobalsHaveLowestPrecedenceAndImportFromPostman() throws {
        var collection = RequestCollection(name: "Scoped", requests: [APIRequest(url: "https://{{host}}/{{region}}/{{shared}}/{{local}}")])
        var defaults = RequestDefaults(); defaults.variables = [Field("shared", "collection"), Field("region", "collection")]; collection.defaults = defaults
        var request = collection.requests[0]; request.variables = [Field("local", "request")]
        let resolved = try RequestInheritance.resolve(request, collection: collection, environment: ["region": "environment"], globals: ["host": "global.test", "region": "global", "shared": "global", "local": "global"])
        XCTAssertEqual(try RequestBuilder.build(resolved.request, variables: resolved.variables).url?.absoluteString, "https://global.test/environment/collection/request")
        let file = #"{"name":"Globals","_postman_variable_scope":"globals","values":[{"key":"host","value":"api.test","enabled":true},{"key":"off","value":"x","enabled":false}]}"#
        let globals = try CollectionCodec.decode(Data(file.utf8)).workspace
        XCTAssertEqual(globals.globalValues, ["host": "api.test"]); XCTAssertTrue(globals.collections.isEmpty && globals.environments.isEmpty)
    }
    func testSyncCarriesGlobalsButStripsSecretValues() throws {
        var workspace = Workspace(); workspace.globals = [Field("region", "eu"), Field("api_token", "global-private")]
        var state = WorkspaceSyncState(); try state.capture(workspace)
        for record in state.records { XCTAssertFalse(String(decoding: record.payload ?? Data(), as: UTF8.self).contains("global-private")) }
        let fresh = try state.workspace(local: Workspace())
        XCTAssertEqual(fresh.globals?.first?.value, "eu"); XCTAssertEqual(fresh.globals?.last?.value, "")
        XCTAssertEqual(try state.workspace(local: workspace).globals?.last?.value, "global-private")
        var other = Workspace(); other.globals = [Field("kept", "local")]
        XCTAssertEqual(try WorkspaceSyncState().workspace(local: other).globals?.first?.name, "kept")
    }
    func testDocumentationRoundTripsThroughPostmanInsomniaAndOpenAPI() throws {
        let postman = ##"{"info":{"name":"Docs","description":{"content":"# Collection docs","type":"text/markdown"},"schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[{"name":"Folder","description":"Folder **docs**","item":[{"name":"Get","request":{"method":"GET","url":"https://example.com","description":"Request `docs`"}}]}]}"##
        let imported = try CollectionCodec.decode(Data(postman.utf8)).workspace
        let collection = try XCTUnwrap(imported.collections.first)
        XCTAssertEqual(collection.defaults?.description, "# Collection docs"); XCTAssertEqual(collection.folders?.first?.defaults.description, "Folder **docs**"); XCTAssertEqual(collection.requests.first?.description, "Request `docs`")
        let again = try XCTUnwrap(CollectionCodec.decode(CollectionCodec.encode(imported, format: .postman)).workspace.collections.first)
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: CollectionCodec.encode(imported, format: .postman)) as? [String: Any])
        let item = try XCTUnwrap((exported["item"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["description"] as? String, "# Collection docs")
        XCTAssertEqual(again.requests.first?.description, "Request `docs`"); XCTAssertEqual(again.folders?.first { $0.name == "Folder" }?.defaults.description, "Folder **docs**"); XCTAssertEqual(again.folders?.first { $0.name == "Docs" }?.defaults.description, "# Collection docs")
        XCTAssertEqual(try CollectionCodec.decode(CollectionCodec.encode(imported, format: .insomnia)).workspace.collections.first?.requests.first?.description, "Request `docs`")
        let spec = "openapi: 3.0.0\ninfo: {title: Docs, version: '1'}\nservers: [{url: 'https://api.example.com'}]\npaths:\n  /pets:\n    get:\n      summary: List pets\n      description: Returns **all** pets.\n      responses: {'200': {description: ok}}\n"
        XCTAssertEqual(try OpenAPICodec.decode(Data(spec.utf8)).workspace.collections.first?.requests.first?.description, "Returns **all** pets.")
        XCTAssertNil(try JSONDecoder().decode(APIRequest.self, from: JSONEncoder().encode(APIRequest())).description)
    }
    func testExamplesRoundTripThroughPostmanAndBecomeMocks() throws {
        let postman = #"{"info":{"name":"Examples","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[{"name":"Pet","request":{"method":"GET","url":"https://example.com/pets/1"},"response":[{"name":"Found","code":200,"status":"OK","header":[{"key":"Content-Type","value":"application/json"}],"body":"{\"id\":1}"},{"name":"Missing","code":404,"body":"not found"}]}]}"#
        let request = try XCTUnwrap(CollectionCodec.decode(Data(postman.utf8)).workspace.collections.first?.requests.first)
        XCTAssertEqual(request.examples?.map(\.name), ["Found", "Missing"]); XCTAssertEqual(request.examples?.map(\.status), [200, 404])
        XCTAssertEqual(request.examples?.first?.headers.first?.value, "application/json"); XCTAssertEqual(request.examples?.first?.body, #"{"id":1}"#)
        let exported = try CollectionCodec.encode(Workspace(collections: [RequestCollection(name: "Examples", requests: [request])]), format: .postman)
        let item = (((try JSONSerialization.jsonObject(with: exported) as? [String: Any])?["item"] as? [[String: Any]])?.first?["item"] as? [[String: Any]])?.first; XCTAssertEqual((item?["response"] as? [[String: Any]])?.map { $0["_postman_previewlanguage"] as? String }, ["json", "text"])
        let again = try XCTUnwrap(CollectionCodec.decode(exported).workspace.collections.first?.requests.first)
        XCTAssertEqual(again.examples?.map(\.name), ["Found", "Missing"]); XCTAssertEqual(again.examples?.last?.body, "not found")
        let mock = MockResponse(example: try XCTUnwrap(again.examples?.last))
        XCTAssertTrue(mock.enabled); XCTAssertEqual(mock.status, 404); XCTAssertEqual(mock.body, "not found")
        let response = APIResponse(status: 201, headers: [Field("Content-Length", "2"), Field("X-Id", "7")], body: Data("ok".utf8), duration: 0.1, url: "https://example.com")
        let saved = try ResponseExample(name: "Created", response: response)
        XCTAssertEqual(saved.headers.map(\.name), ["X-Id"]); XCTAssertEqual(saved.body, "ok")
        XCTAssertThrowsError(try ResponseExample(name: "Binary", response: APIResponse(status: 200, headers: [], body: Data([0xff, 0xfe]), duration: 0, url: "")))
    }
    func testPostmanRawLanguagesKeepTheirContentType() throws {
        let postman = #"{"info":{"name":"Raw","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[{"name":"Soap","request":{"method":"POST","url":"https://example.com/soap","body":{"mode":"raw","raw":"<a/>","options":{"raw":{"language":"xml"}}}}},{"name":"Typed","request":{"method":"POST","url":"https://example.com","header":[{"key":"Content-Type","value":"text/xml; charset=utf-8"}],"body":{"mode":"raw","raw":"<b/>","options":{"raw":{"language":"xml"}}}}}]}"#
        let requests = try XCTUnwrap(CollectionCodec.decode(Data(postman.utf8)).workspace.collections.first?.requests)
        XCTAssertEqual(requests[0].headers.filter { $0.name == "Content-Type" }.map(\.value), ["application/xml"]); XCTAssertEqual(requests[0].bodyKind, .text)
        XCTAssertEqual(requests[1].headers.filter { $0.name == "Content-Type" }.map(\.value), ["text/xml; charset=utf-8"])
        let exported = String(decoding: try CollectionCodec.encode(Workspace(collections: [RequestCollection(name: "Raw", requests: requests)]), format: .postman), as: UTF8.self)
        XCTAssertFalse(exported.contains(#""language" : "text""#)); XCTAssertTrue(exported.contains("xml"))
    }
    func testBulkEditRoundTripsAndKeepsFieldIdentity() {
        var secret = Field("X-Token", "abc"); secret.secret = true
        let fields = [Field("Accept", "application/json"), secret, Field("Off", "x:y", enabled: false), Field("", "")]
        let text = FieldBulkText.encode(fields)
        XCTAssertEqual(text, "Accept:application/json\nX-Token:abc\n//Off:x:y")
        let decoded = FieldBulkText.decode(text + "\n\n  New : value \n// Spaced:1\nflag", existing: fields)
        XCTAssertEqual(decoded.map(\.name), ["Accept", "X-Token", "Off", "New", "Spaced", "flag"])
        XCTAssertEqual(decoded.map(\.value), ["application/json", "abc", "x:y", "value", "1", ""])
        XCTAssertEqual(decoded.map(\.enabled), [true, true, false, true, false, true])
        XCTAssertEqual(decoded[1].id, secret.id); XCTAssertEqual(decoded[1].secret, true)
    }
}

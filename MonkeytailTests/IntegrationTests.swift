import XCTest
@testable import MonkeytailCore
@testable import Monkeytail
import AVFoundation

@MainActor
final class IntegrationTests: XCTestCase {
    func testMIMEPreviewsValidateDataAndPreserveBytes() async throws {
        for (path, kind, ext) in [("png", ResponseBodyKind.image, "png"), ("wav", .audio, "wav"), ("mp4", .video, "mp4"), ("binary", .binary, "bin"), ("fake-image", .binary, "png")] {
            let response = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/media/" + path)))
            let preview = ResponsePreview(response: response)
            XCTAssertEqual(preview.kind, kind, path)
            XCTAssertEqual(preview.fileExtension, ext, path)
            XCTAssertEqual(preview.bytes, Array(response.body), path)
            if kind == .image { XCTAssertEqual(preview.image?.width, 64) }
            if kind == .audio || kind == .video {
                let url = try XCTUnwrap(preview.mediaURL)
                XCTAssertEqual(try Data(contentsOf: url), response.body)
                let asset = ResponseMediaView.asset(for: url)
                XCTAssertEqual(asset.referenceRestrictions, .forbidAll)
                let playable = try await asset.load(.isPlayable)
                XCTAssertTrue(playable, path)
            }
        }
    }

    func testTextMIMEAndPreviewByteLimit() {
        let body = Data(("a" + String(repeating: "é", count: 500_000)).utf8)
        let response = APIResponse(status: 200, headers: [Field("CONTENT-TYPE", "Text/Plain; charset=UTF-8")], body: body, duration: 0, url: "https://example.com")
        let preview = ResponsePreview(response: response)
        XCTAssertEqual(preview.kind, .text)
        XCTAssertEqual(preview.defaultFormat, "Raw")
        XCTAssertEqual(preview.bytes.count, 1_000_000)
        XCTAssertEqual(response.body.count, 1_000_001)
        XCTAssertFalse(preview.rawLines.isEmpty)
    }

    func testMediaCacheFollowsResponseLifetime() async throws {
        let response = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/media/wav")))
        var preview: ResponsePreview? = ResponsePreview(response: response)
        let url = try XCTUnwrap(preview?.mediaURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        preview = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testBrowserTLSAndHTTP2FingerprintsOnTheWire() async throws {
        let ca = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/tls-ca"))).body
        let request = try RequestBuilder.build(APIRequest(url: "https://localhost:8769/"))
        var fingerprints: [BrowserProfile: [String: Any]] = [:]
        for profile in BrowserProfile.allCases {
            let response = try await BrowserHTTPClient(certificateAuthorities: ca).send(request, proxy: ProxySettings(), impersonation: BrowserImpersonation(profile: profile))
            XCTAssertEqual(response.status, 200, profile.rawValue)
            let fingerprint = try XCTUnwrap(try JSONTools.parse(response.text) as? [String: Any])
            fingerprints[profile] = fingerprint
            XCTAssertEqual(fingerprint["negotiatedALPN"] as? String, "h2")
            XCTAssertEqual(fingerprint["alpn"] as? [String], ["h2", "http/1.1"])
            XCTAssertFalse((fingerprint["ciphers"] as? [Int] ?? []).isEmpty)
        }
        let chrome = try XCTUnwrap(fingerprints[.chrome])
        let safari = try XCTUnwrap(fingerprints[.safariIOS])
        XCTAssertEqual(chrome["http2Settings"] as? [[Int]], [[1, 65536], [2, 0], [4, 6291456], [6, 262144]])
        XCTAssertEqual(safari["http2Settings"] as? [[Int]], [[2, 0], [3, 100], [4, 2097152], [9, 1]])
        func withoutGrease(_ values: Any?) -> [Int] { (values as? [Int] ?? []).filter { $0 & 0x0f0f != 0x0a0a } }
        XCTAssertNotEqual(withoutGrease(chrome["ciphers"]), withoutGrease(safari["ciphers"]))
        XCTAssertNotEqual(withoutGrease(chrome["extensions"]).sorted(), withoutGrease(safari["extensions"]).sorted())
    }

    func testBrowserTransportRejectsUntrustedCertificates() async throws {
        do {
            _ = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "https://localhost:8769/")), impersonation: BrowserImpersonation(profile: .chrome))
            XCTFail("An untrusted fixture certificate must be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.lowercased().contains("certificate"), error.localizedDescription) }
    }

    func testBrowserHeadersBodyProxiesAndRedirects() async throws {
        var model = APIRequest(method: "POST", url: "http://127.0.0.1:8766/echo")
        model.bodyKind = .text; model.body = "Hello\0Browser"
        model.headers = [Field("User-Agent", "Monkeytail debug"), Field("X-Debug", "yes")]
        let profile = BrowserImpersonation(profile: .chrome)
        let response = try await HTTPClient().send(RequestBuilder.build(model), impersonation: profile)
        let echoed = try JSONTools.parse(response.text) as! [String: Any]
        let headers = (echoed["headers"] as! [String: String]).reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
        XCTAssertEqual(echoed["body"] as? String, model.body)
        XCTAssertEqual(headers["user-agent"], "Monkeytail debug")
        XCTAssertEqual(headers["x-debug"], "yes")
        XCTAssertNotNil(headers["sec-ch-ua"])
        let plain = try await HTTPClient().send(RequestBuilder.build(model), impersonation: BrowserImpersonation(profile: .chrome, browserHeaders: false))
        let plainHeaders = (try JSONTools.parse(plain.text) as! [String: Any])["headers"] as! [String: String]
        XCTAssertFalse(plainHeaders.keys.contains { $0.lowercased() == "sec-ch-ua" })
        model.url = "http://monkeytail.test:8766/echo"
        for kind in [ProxyKind.http, .socks] {
            var proxy = ProxySettings(); proxy.kind = kind; proxy.host = "127.0.0.1"; proxy.port = kind == .http ? "8767" : "8768"
            let result = try await HTTPClient().send(RequestBuilder.build(model), proxy: proxy, impersonation: profile)
            XCTAssertEqual(result.status, 200)
        }
        model.url = "http://127.0.0.1:8766/cross-origin"
        model.headers += [Field("Authorization", "Bearer secret"), Field("Cookie", "token=secret"), Field("Proxy-Authorization", "Basic secret")]
        let cross = try await HTTPClient().send(RequestBuilder.build(model), impersonation: profile)
        let crossHeaders = (try JSONTools.parse(cross.text) as! [String: Any])["headers"] as! [String: String]
        XCTAssertFalse(crossHeaders.keys.contains { ["authorization", "cookie", "proxy-authorization"].contains($0.lowercased()) })
        let stopped = try await HTTPClient(followRedirects: false).send(RequestBuilder.build(model), impersonation: profile)
        XCTAssertEqual(stopped.status, 302)
    }

    func testBrowserResponseLimitAndCancellation() async throws {
        let profile = BrowserImpersonation(profile: .chrome)
        do {
            _ = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/oversize")), impersonation: profile)
            XCTFail("Expected response limit")
        } catch { XCTAssertTrue(error.localizedDescription.contains("20 MB")) }
        let task = Task { try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/slow")), impersonation: profile) }
        try await Task.sleep(for: .milliseconds(100))
        let started = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }

    func testPreRequestScriptMutationsAndConsole() async throws {
        let result = try await ScriptRunner().run("request.headers['X-Test'] = 'yes'; environment.set('token', 'abc'); console.log('ready');", request: APIRequest(), variables: [:])
        XCTAssertEqual(result.request.headers["X-Test"], "yes")
        XCTAssertEqual(result.variables["token"], "abc")
        XCTAssertEqual(result.logs.first?.message, "ready")
    }

    func testPostResponseAssertionsAndAliases() async throws {
        let response = APIResponse(status: 200, headers: [], body: Data(#"{"token":"abc"}"#.utf8), duration: 0.1, url: "https://example.com")
        let result = try await ScriptRunner().run("pm.test('OK', () => pm.response.to.have.status(200)); test('Fails', () => assert(false, 'expected')); pm.environment.set('token', response.json().token);", request: APIRequest(), response: response, variables: [:])
        XCTAssertEqual(result.logs.map(\.level), ["pass", "fail"])
        XCTAssertEqual(result.variables["token"], "abc")
    }

    func testScriptExceptionAndTimeoutRecovery() async throws {
        do { _ = try await ScriptRunner().run("throw new Error('Oops');", request: APIRequest(), variables: [:]); XCTFail("Expected exception") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Oops")) }
        do { _ = try await ScriptRunner().run("while (true) {}", request: APIRequest(), variables: [:], timeout: 1); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("time limit")) }
        let result = try await ScriptRunner().run("console.log('recovered')", request: APIRequest(), variables: [:])
        XCTAssertEqual(result.logs.first?.message, "recovered")
    }

    func testScriptNetworkIsBlocked() async throws {
        let result = try await ScriptRunner().run("try { await fetch('http://127.0.0.1:8766/echo'); console.log('unexpected'); } catch(e) { console.log('blocked'); }", request: APIRequest(), variables: [:])
        XCTAssertEqual(result.logs.first?.message, "blocked")
    }

    func testHTTPTransportHeadersBodyAndQuery() async throws {
        var model = APIRequest(method: "POST", url: "http://127.0.0.1:8766/echo")
        model.headers = [Field("X-Test", "native-swift")]
        model.query = [Field("q", "hello + world & more")]
        model.bodyKind = .json; model.body = #"{"hello":"world"}"#
        let response = try await HTTPClient().send(RequestBuilder.build(model))
        XCTAssertEqual(response.status, 200)
        let json = try JSONTools.parse(response.text) as! [String: Any]
        XCTAssertEqual(json["method"] as? String, "POST")
        XCTAssertEqual(json["body"] as? String, model.body)
        XCTAssertEqual((json["headers"] as? [String: String])?["X-Test"], "native-swift")
        XCTAssertEqual((json["query"] as? [String: [String]])?["q"], ["hello + world & more"])
    }

    func testRedirectControlAndCredentialStripping() async throws {
        let request = try RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/redirect"))
        let stopped = try await HTTPClient(followRedirects: false).send(request)
        XCTAssertEqual(stopped.status, 302)
        let followed = try await HTTPClient().send(request)
        XCTAssertEqual(followed.status, 200)
        var model = APIRequest(url: "http://127.0.0.1:8766/cross-origin")
        model.headers = [Field("Authorization", "Bearer secret"), Field("Cookie", "token=secret")]
        let cross = try await HTTPClient().send(RequestBuilder.build(model))
        let json = try JSONTools.parse(cross.text) as! [String: Any]
        let headers = json["headers"] as! [String: String]
        XCTAssertFalse(headers.keys.contains { ["authorization", "cookie"].contains($0.lowercased()) })
    }

    func testResponseLimitAndCancellation() async throws {
        do { _ = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/oversize"))); XCTFail("Expected size error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("20 MB")) }
        let task = Task { try await HTTPClient().send(RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/slow"))) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { }
    }

    func testHTTPConnectAndSOCKSProxies() async throws {
        let request = try RequestBuilder.build(APIRequest(url: "http://monkeytail.test:8766/echo"))
        for kind in [ProxyKind.http, .socks] {
            var proxy = ProxySettings(); proxy.kind = kind; proxy.host = "127.0.0.1"; proxy.port = kind == .http ? "8767" : "8768"
            let response = try await HTTPClient().send(request, proxy: proxy)
            XCTAssertEqual(response.status, 200)
        }
    }

    func testPersistenceAndImportDoNotReplaceWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory)
        let originalCount = store.requestCount
        try store.importContent("curl-impersonate --impersonate firefox147:no https://example.com -H 'X-Test: yes'")
        XCTAssertEqual(store.requestCount, originalCount + 1)
        XCTAssertEqual(store.selectedRequest?.impersonation, BrowserImpersonation(profile: .firefox, browserHeaders: false))
        store.save()
        let restored = WorkspaceStore(directory: directory)
        XCTAssertEqual(restored.workspace, store.workspace)
    }

    func testStoreRunsHooksAroundTransportAndPersistsVariables() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory)
        var request = store.selectedRequest!
        request.url = "http://127.0.0.1:8766/echo"; request.method = "POST"
        request.bodyKind = .json; request.body = "{}"; request.scriptsEnabled = true
        request.preScript = "request.headers['X-Trace-ID'] = crypto.randomUUID(); request.body = JSON.stringify({ok: true}); environment.set('phase', 'pre');"
        request.postScript = "test('OK', () => assert(response.status === 200)); environment.set('method', response.json().method);"
        store.update(request); store.send()
        let deadline = Date().addingTimeInterval(15)
        while store.runningID != nil && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(store.runningID)
        XCTAssertNil(store.errors[request.id])
        let prepared = try XCTUnwrap(store.responses[request.id])
        let response = prepared.response
        XCTAssertEqual(prepared.preview.responseID, response.id)
        XCTAssertTrue(prepared.preview.rawLines.joined(separator: "\n").contains("Hello from Monkeytail"))
        XCTAssertNotNil(prepared.preview.tree)
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.logs.first?.level, "pass")
        XCTAssertEqual(store.variables["phase"], "pre")
        XCTAssertEqual(store.variables["method"], "POST")
        let echo = try JSONTools.parse(response.text) as! [String: Any]
        XCTAssertEqual(echo["body"] as? String, #"{"ok":true}"#)
        XCTAssertNotNil((echo["headers"] as? [String: String])?["X-Trace-ID"])
    }
}

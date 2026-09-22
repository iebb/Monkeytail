import XCTest
import MonkeytailCore
@testable import Monkeytail

@MainActor
final class IntegrationTests: XCTestCase {
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
        try store.importContent("curl https://example.com -H 'X-Test: yes'")
        XCTAssertEqual(store.requestCount, originalCount + 1)
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
        let response = try XCTUnwrap(store.responses[request.id])
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.logs.first?.level, "pass")
        XCTAssertEqual(store.variables["phase"], "pre")
        XCTAssertEqual(store.variables["method"], "POST")
        let echo = try JSONTools.parse(response.text) as! [String: Any]
        XCTAssertEqual(echo["body"] as? String, #"{"ok":true}"#)
        XCTAssertNotNil((echo["headers"] as? [String: String])?["X-Trace-ID"])
    }
}

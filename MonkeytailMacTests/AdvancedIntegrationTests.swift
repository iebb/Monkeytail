import XCTest
import MonkeytailCore
#if os(macOS)
@testable import MonkeytailMac
#else
@testable import Monkeytail
#endif

@MainActor final class AdvancedIntegrationTests: XCTestCase {
    private func wait(_ predicate: () -> Bool, timeout: Double = 8) async throws {
        let limit = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < limit { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(predicate(), "Timed out waiting for the operation")
    }
    func testRedirectCookiesStayScopedAndAdvancedCredentialsDoNotLeak() async throws {
        for profile in [BrowserImpersonation?.none, BrowserImpersonation(profile: .chrome)] {
            let redirect = try RequestBuilder.build(APIRequest(url: "http://127.0.0.1:8766/cookie-redirect"))
            let response = try await HTTPClient().send(redirect, impersonation: profile, cookies: CookieJar())
            let object = try JSONTools.parse(response.text) as! [String: Any]
            let headers = (object["headers"] as! [String: String]).reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
            XCTAssertEqual(headers["cookie"], "fixture=redirect"); XCTAssertEqual(response.sessionCookies?.first?.httpOnly, true)
            var request = APIRequest(url: "http://127.0.0.1:8766/cross-origin"); request.headers = [Field("X-Custom", "private"), Field("X-Amz-Security-Token", "aws-private"), Field("X-API-Key", "api-private")]
            let crossed = try await HTTPClient().send(RequestBuilder.build(request), impersonation: profile, sensitiveHeaders: ["X-Custom"])
            let echoed = try JSONTools.parse(crossed.text) as! [String: Any]
            let safe = (echoed["headers"] as! [String: String]).reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
            XCTAssertNil(safe["x-custom"]); XCTAssertNil(safe["x-amz-security-token"]); XCTAssertNil(safe["x-api-key"])
        }
    }
    func testStoreRefreshesOAuthAndRunsInheritedScriptsAndAssertions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory)
        var folder = RequestFolder(name: "Auth"); folder.defaults.auth.kind = .oauth2; var oauth = OAuthConfiguration(); oauth.tokenURL = "http://127.0.0.1:8766/oauth/token"; oauth.clientID = "fixture"; oauth.refreshToken = "fixture-refresh"; oauth.expiresAt = .distantPast; folder.defaults.auth.oauth = oauth
        folder.defaults.scriptsEnabled = true; folder.defaults.preScript = "request.headers['X-Inherited'] = 'yes';"
        var request = APIRequest(url: "http://127.0.0.1:8766/echo"); request.auth.kind = .inherit; request.folderID = folder.id; request.assertions = [ResponseAssertion()]
        var collection = RequestCollection(name: "Fixture", requests: [request]); collection.folders = [folder]; store.workspace = Workspace(collections: [collection]); store.selectedRequestID = request.id
        store.send(); try await wait { store.runningID == nil }
        XCTAssertNil(store.errors[request.id]); let response = try XCTUnwrap(store.responses[request.id]?.response)
        let object = try JSONTools.parse(response.text) as! [String: Any], headers = (object["headers"] as! [String: String]).reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
        XCTAssertEqual(headers["authorization"], "Bearer fixture-access"); XCTAssertEqual(headers["x-inherited"], "yes"); XCTAssertEqual(store.testResults[request.id]?.first?.passed, true)
        XCTAssertEqual(store.workspace.collections.first?.folders?.first?.defaults.auth.oauth?.refreshToken, "fixture-rotated")
    }
    func testOfflineAndLoopbackMocksSnapshotsAndStatus() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var request = APIRequest(url: "https://unreachable.invalid/example"); var mock = MockResponse(); mock.enabled = true; mock.status = 201; mock.body = "{\"mock\":42}"; request.mock = mock
        store.workspace = Workspace(collections: [RequestCollection(name: "Mocks", requests: [request])]); store.selectedRequestID = request.id
        store.send(); try await wait { store.runningID == nil }; XCTAssertEqual(store.responses[request.id]?.response.status, 201)
        store.mockServer.start([request], variables: [:]); defer { store.mockServer.stop() }
        try await wait { store.mockServer.address != nil || store.mockServer.error != nil }
        let url = try XCTUnwrap(store.mockServer.address) + "/example"
        let response = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: url)))
        XCTAssertEqual(response.status, 201); XCTAssertEqual(response.text, mock.body)
        let missing = try await HTTPClient().send(RequestBuilder.build(APIRequest(url: store.mockServer.address! + "/missing"))); XCTAssertEqual(missing.status, 404)
        var snapshot = ResponseSnapshot(request: request, response: response); snapshot.response.status = 503
        try store.useSnapshotAsMock(snapshot); XCTAssertEqual(store.selectedRequest?.mock?.status, 503)
    }
    func testWebSocketTextBinaryAndSSEDisconnect() async throws {
        let live = LiveSession(); var request = APIRequest(url: "ws://127.0.0.1:8766/websocket"); request.transport = .websocket
        live.connect(request, variables: [:], proxy: ProxySettings()); defer { live.disconnect() }
        try await wait { live.connected || live.error != nil }; XCTAssertNil(live.error); XCTAssertTrue(live.connected)
        live.send("{\"message\":42}", binary: false); try await wait { live.events.contains { $0.direction == "Received" && $0.text.contains("42") } }
        live.send("00 ff 80", binary: true); try await wait { live.events.contains { $0.direction == "Received" && $0.binary == Data([0, 255, 128]) } }
        live.disconnect(); XCTAssertFalse(live.connected)
        request.transport = .sse; request.url = "http://127.0.0.1:8766/events"; live.clear(); live.connect(request, variables: [:], proxy: ProxySettings())
        try await wait { !live.events.isEmpty || live.error != nil }; XCTAssertNil(live.error); XCTAssertEqual(live.events.first?.type, "update"); XCTAssertEqual(live.events.first?.text, "{\"value\":42}")
        live.disconnect(); XCTAssertFalse(live.connecting)
    }

    func testValidClientIdentityAndCertificateValidity() async throws {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8766/client-identity")!)
        let identity = try TLSConfiguration.importPKCS12(data, password: "fixture", host: "LOCALHOST", port: 8769)
        XCTAssertEqual(identity.host, "localhost"); XCTAssertEqual(identity.port, 8769)
        let certificate = try XCTUnwrap(identity.certificates.first)
        let details = CertificateDetails(certificate)
        XCTAssertEqual(details.subject, "Monkeytail Local Test CA"); XCTAssertEqual(details.sha256.count, 95)
        XCTAssertLessThanOrEqual(try XCTUnwrap(details.notBefore), Date()); XCTAssertGreaterThan(try XCTUnwrap(details.notAfter), Date())
        XCTAssertThrowsError(try TLSConfiguration.importPKCS12(data, password: "wrong", host: "localhost"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = LocalNetworkStorage(directory: directory)
        try storage.addIdentity(.init(host: "localhost", port: 8769, filename: "client.p12", data: data, password: "fixture"))
        XCTAssertNotNil(try storage.identity(for: URL(string: "https://localhost:8769")))
        XCTAssertNil(try storage.identity(for: URL(string: "https://other.test:8769")))
        XCTAssertNil(try storage.identity(for: URL(string: "https://localhost:443")))
    }

    func testDeviceLocalCookieStorageAndClientIdentityValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = LocalNetworkStorage(directory: directory); var jar = CookieJar(); jar.cookies = [StoredCookie(name: "session", value: "private-cookie", domain: "example.test")]
        let environment = UUID(); try storage.setJar(jar, environment: environment)
        let restored = LocalNetworkStorage(directory: directory); XCTAssertEqual(restored.jar(environment).cookies, jar.cookies); XCTAssertTrue(restored.jar(UUID()).cookies.isEmpty)
        XCTAssertThrowsError(try TLSConfiguration.importPKCS12(Data("invalid".utf8), password: "wrong", host: "example.test"))
    }
    func testWorkspaceCredentialsSurviveBothStorageSwitches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); try? SecretVault(directory: directory, useKeychain: true).remove() }
        let store = WorkspaceStore(directory: directory)
        var request = try XCTUnwrap(store.selectedRequest)
        request.auth.kind = .bearer; request.auth.token = "storage-token"
        request.headers.append(Field("X-API-Key", "storage-key"))
        store.update(request); store.save()
        XCTAssertFalse(store.useKeychain); XCTAssertTrue(store.syncCredentials); XCTAssertFalse(store.hideCredentials)
        var raw = try String(contentsOf: directory.appendingPathComponent("workspace.json"), encoding: .utf8)
        XCTAssertTrue(raw.contains("storage-token")); XCTAssertTrue(raw.contains("storage-key"))
        store.setUseKeychain(true); XCTAssertNil(store.issue); XCTAssertTrue(store.useKeychain)
        raw = try String(contentsOf: directory.appendingPathComponent("workspace.json"), encoding: .utf8)
        XCTAssertFalse(raw.contains("storage-token")); XCTAssertFalse(raw.contains("storage-key"))
        let secure = WorkspaceStore(directory: directory)
        XCTAssertEqual(secure.selectedRequest?.auth.token, "storage-token")
        secure.setUseKeychain(false); XCTAssertNil(secure.issue)
        let plain = WorkspaceStore(directory: directory)
        XCTAssertEqual(plain.selectedRequest?.auth.token, "storage-token")
        XCTAssertEqual(plain.selectedRequest?.headers.last?.value, "storage-key")
        XCTAssertTrue(try SecretVault(directory: directory, useKeychain: true).load().isEmpty)
    }
    func testLegacyKeychainMigrationPreservesSharingPreferences() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); try? SecretVault(directory: directory, useKeychain: true).remove() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var workspace = Workspace.starter
        workspace.collections[0].requests[0].auth.token = "old-vault-token"
        var secrets: [String: String] = [:]
        let protected = SecretPolicy.strip(workspace, secrets: &secrets, files: false)
        try SecretVault(directory: directory, useKeychain: true).save(secrets)
        try JSONEncoder().encode(protected).write(to: directory.appendingPathComponent("workspace.json"))
        try Data("{\"syncEnabled\":false,\"edited\":true}".utf8).write(to: directory.appendingPathComponent("settings.json"))
        let store = WorkspaceStore(directory: directory)
        XCTAssertFalse(store.useKeychain); XCTAssertFalse(store.syncCredentials); XCTAssertTrue(store.hideCredentials)
        XCTAssertEqual(store.selectedRequest?.auth.token, "")
        store.setUseKeychain(true); XCTAssertNil(store.issue)
        XCTAssertEqual(store.selectedRequest?.auth.token, "old-vault-token")
        store.setUseKeychain(false); XCTAssertNil(store.issue)
        store.save(); XCTAssertNil(store.issue)
        let restored = WorkspaceStore(directory: directory)
        XCTAssertEqual(restored.selectedRequest?.auth.token, "old-vault-token")
        XCTAssertTrue(try SecretVault(directory: directory, useKeychain: true).load().isEmpty)
    }
    func testCookieStorageCanSwitchBetweenFilesAndKeychain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = LocalNetworkStorage(directory: directory)
        var jar = CookieJar(); jar.cookies = [StoredCookie(name: "session", value: "switch-cookie", domain: "example.test")]
        try storage.setJar(jar, environment: nil)
        try storage.setUseKeychain(true)
        XCTAssertEqual(LocalNetworkStorage(directory: directory, useKeychain: true).jar(nil).cookies, jar.cookies)
        try storage.setUseKeychain(false)
        XCTAssertEqual(LocalNetworkStorage(directory: directory).jar(nil).cookies, jar.cookies)
    }

}

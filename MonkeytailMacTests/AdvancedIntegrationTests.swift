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
    func testCollectionRunUsesDataRowsCarriesVariablesAndFollowsDirectives() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory)
        var login = APIRequest(name: "Login", url: "http://127.0.0.1:8766/echo"); login.scriptsEnabled = true
        login.postScript = "pm.environment.set('token', 'tok-' + pm.iterationData.get('user')); pm.test('iteration count', () => pm.expect(pm.info.iterationCount).to.equal(2));"
        var skipped = APIRequest(name: "Skip me", url: "http://127.0.0.1:8766/echo"); skipped.scriptsEnabled = true; skipped.preScript = "pm.execution.skipRequest();"
        var profile = APIRequest(name: "Profile", url: "http://127.0.0.1:8766/echo?u={{user}}"); profile.scriptsEnabled = true
        profile.headers = [Field("Authorization", "Bearer {{token}}"), Field("X-Id", "{{$guid}}")]
        profile.postScript = """
        const data = pm.response.json();
        const headers = Object.fromEntries(Object.entries(data.headers).map(([k, v]) => [k.toLowerCase(), v]));
        pm.test('token carried', () => pm.expect(headers['authorization']).to.equal('Bearer tok-' + pm.iterationData.get('user')));
        pm.test('query from data', () => pm.expect(data.query.u[0]).to.equal(pm.iterationData.get('user')));
        pm.test('dynamic guid', () => assert(/^[0-9a-f-]{36}$/.test(headers['x-id']), headers['x-id']));
        if (pm.info.iteration === 1) postman.setNextRequest(null);
        """
        let final = APIRequest(name: "Final", url: "http://127.0.0.1:8766/echo")
        let collection = RequestCollection(name: "Run", requests: [login, skipped, profile, final])
        store.workspace = Workspace(collections: [collection])
        let rows = try RunnerData.parse(Data("user\nada\ngrace\n".utf8))
        store.startRun(collectionID: collection.id, folderID: nil, configuration: RunConfiguration(requestIDs: Set(collection.requests.map(\.id)), iterations: rows.count, data: rows))
        let run = try XCTUnwrap(store.collectionRun)
        try await wait({ !run.running }, timeout: 20)
        XCTAssertEqual(run.report.results.map(\.name), ["Login", "Skip me", "Profile", "Final", "Login", "Skip me", "Profile"])
        XCTAssertEqual(run.report.results.map(\.skipped), [false, true, false, false, false, true, false])
        XCTAssertEqual(run.report.failedCount, 0, run.report.results.flatMap(\.tests).filter { !$0.passed }.map(\.name).joined(separator: "\n"))
        XCTAssertEqual(run.report.testCount, 8)
        XCTAssertTrue(run.report.results[2].url.hasSuffix("/echo?u=ada"))
    }
    func testPostmanScriptingSendRequestAssertionsAndPathVariables() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceStore(directory: directory)
        var request = APIRequest(name: "Scripted", url: "http://127.0.0.1:8766/users/:id"); request.scriptsEnabled = true
        request.pathVariables = [Field("id", "{{user}}")]
        request.headers = [Field("Authorization", "Bearer {{token}}")]
        request.preScript = """
        pm.sendRequest({url: 'http://127.0.0.1:8766/token', method: 'POST', header: {'Content-Type': 'application/json'}, body: {mode: 'raw', raw: JSON.stringify({grant: 'demo'})}}, (err, res) => {
          if (err) throw err;
          pm.environment.set('token', 'from-' + res.json().method + '-' + res.code);
        });
        const replay = await pm.sendRequest('http://127.0.0.1:8766/second');
        pm.environment.set('second', replay.json().path);
        """
        request.postScript = """
        const tests = 'shadowed safely';
        const data = pm.response.json();
        pm.test('status helpers', () => { pm.response.to.have.status(200); pm.response.to.be.ok; pm.response.to.not.be.error; pm.response.to.be.json; pm.response.to.have.header('content-type'); });
        pm.test('json body', () => pm.response.to.have.jsonBody('data.name', 'Monkeytail'));
        pm.test('chai subset', () => {
          pm.expect(data).to.be.an('object').that.has.property('data').that.is.an('object');
          pm.expect(data).to.have.property('path', '/users/42');
          pm.expect(data.data.platforms).to.include('iPad').and.have.lengthOf(3);
          pm.expect(data.data.native).to.be.true;
          pm.expect(data.missing).to.not.exist;
          pm.expect(pm.response.responseTime).to.be.at.least(0);
          pm.expect(data.data).to.deep.equal({name: 'Monkeytail', native: true, platforms: ['iPhone', 'iPhone Duo', 'iPad']});
          pm.expect(data.data).to.have.all.keys('name', 'native', 'platforms');
          pm.expect('monkeytail').to.match(/tail$/).and.not.be.empty;
          pm.expect(5).to.be.within(1, 10).and.oneOf([4, 5]);
        });
        pm.test('header get is case-insensitive', () => pm.expect(pm.response.headers.get('CONTENT-TYPE')).to.include('json'));
        pm.test('token from sendRequest', () => pm.expect(Object.entries(data.headers).find(([k]) => k.toLowerCase() === 'authorization')[1]).to.equal('Bearer from-POST-200'));
        pm.test('awaited sendRequest', () => pm.expect(pm.environment.get('second')).to.equal('/second'));
        pm.test('failure message', () => pm.expect(1).to.equal(2));
        """
        let collection = RequestCollection(name: "Scripts", requests: [request])
        var environment = APIEnvironment(name: "Env", variables: [Field("user", "42")])
        environment.id = UUID()
        store.workspace = Workspace(collections: [collection], environments: [environment]); store.workspace.selectedEnvironmentID = environment.id
        store.selectedRequestID = request.id
        store.send(); try await wait({ store.runningID == nil }, timeout: 20)
        XCTAssertNil(store.errors[request.id])
        let logs = try XCTUnwrap(store.responses[request.id]?.response.logs)
        XCTAssertEqual(logs.filter { $0.level == "pass" }.map(\.message), ["status helpers", "json body", "chai subset", "header get is case-insensitive", "token from sendRequest", "awaited sendRequest"], logs.map { $0.level + ": " + $0.message }.joined(separator: "\n"))
        XCTAssertEqual(logs.filter { $0.level == "fail" }.map(\.message), ["failure message: expected 1 to equal 2"])
        XCTAssertEqual(store.environment?.values["token"], "from-POST-200")
    }
    func testJWTBearerIsSignedOnSendAndVerifiesWithCryptoJS() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var request = APIRequest(name: "JWT", url: "http://127.0.0.1:8766/echo"); request.variables = [Field("jwtSecret", "s3cr3t"), Field("user", "ada")]
        var jwt = JWTAuth(); jwt.algorithm = .hs256; jwt.secret = "{{jwtSecret}}"; jwt.payload = #"{"sub": "{{user}}", "iat": {{$timestamp}}}"#; request.auth.kind = .jwt; request.auth.jwt = jwt
        request.postScript = """
        const [prefix, token] = pm.response.json().headers['Authorization'].split(' '), [h, p, s] = token.split('.');
        pm.test('prefix', () => pm.expect(prefix).to.equal('Bearer'));
        pm.test('signature', () => pm.expect(CryptoJS.HmacSHA256(h + '.' + p, pm.variables.get('jwtSecret')).toString(CryptoJS.enc.Base64url)).to.equal(s));
        pm.test('claims', () => { const claims = JSON.parse(CryptoJS.enc.Base64url.parse(p).toString(CryptoJS.enc.Utf8)); pm.expect(claims.sub).to.equal('ada'); pm.expect(Math.abs(claims.iat - Date.now() / 1000)).to.be.below(60); });
        """
        store.workspace = Workspace(collections: [RequestCollection(name: "JWT", requests: [request])]); store.selectedRequestID = request.id
        store.send(); try await wait { store.runningID == nil }
        let logs = try XCTUnwrap(store.responses[request.id]?.response.logs)
        XCTAssertEqual(logs.filter { $0.level == "pass" }.map(\.message), ["prefix", "signature", "claims"], logs.map(\.message).joined(separator: "\n"))
    }
    func testLegacyPostmanTestsGlobal() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var request = APIRequest(url: "http://127.0.0.1:8766/echo"); request.scriptsEnabled = true
        request.postScript = "tests['Status code is 200'] = responseCode.code === 200; tests['Body has message'] = responseBody.has ? false : JSON.parse(responseBody).message.length > 0; tests['fails'] = false;"
        store.workspace = Workspace(collections: [RequestCollection(name: "Legacy", requests: [request])]); store.selectedRequestID = request.id
        store.send(); try await wait { store.runningID == nil }
        let logs = try XCTUnwrap(store.responses[request.id]?.response.logs)
        XCTAssertEqual(logs.filter { $0.level == "pass" }.map(\.message), ["Status code is 200", "Body has message"])
        XCTAssertEqual(logs.filter { $0.level == "fail" }.map(\.message), ["fails"])
    }
    func testImportedClientScriptAPIsRunUnchanged() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var request = APIRequest(name: "Imported", url: "http://127.0.0.1:8766/echo"); request.scriptsEnabled = true
        request.preScript = "req.setHeader('X-From-Bru', bru.getEnvVar('seed'));"
        request.postScript = """
        var data = pm.response.json();
        bru.setVar('fromBru', data.path);
        test('bru', () => { expect(res.getStatus()).to.equal(200); expect(bru.getVar('fromBru')).to.equal('/echo'); expect(Object.entries(data.headers).find(([k]) => k.toLowerCase() === 'x-from-bru')[1]).to.equal('seeded'); });
        insomnia.test('insomnia', () => insomnia.expect(insomnia.response.code).to.equal(200));
        pw.test('hoppscotch', () => { pw.expect(pw.response.status).toBe(200); pw.expect(pw.response.status).toBeLevel2xx(); pw.expect('monkeytail').not.toInclude('x'); pw.env.set('fromHopp', 'h'); });
        tc.check('thunder', () => tc.response.json.path, 'equal', '/echo'); tc.setVar('fromThunder', 't');
        await (async (client, request, response) => {
          client.global.set('fromJetBrains', response.contentType.mimeType);
          client.test('jetbrains', () => client.assert(response.status === 200 && response.body.path === '/echo', 'status'));
        })(__http.client, __http.request, __http.response).catch(e => { if (!e || !e.__exit) throw e; });
        """
        var environment = APIEnvironment(name: "Env", variables: [Field("seed", "seeded")]); environment.id = UUID()
        store.workspace = Workspace(collections: [RequestCollection(name: "Imported", requests: [request])], environments: [environment]); store.workspace.selectedEnvironmentID = environment.id
        store.selectedRequestID = request.id
        store.send(); try await wait { store.runningID == nil }
        XCTAssertNil(store.errors[request.id])
        let logs = try XCTUnwrap(store.responses[request.id]?.response.logs)
        XCTAssertEqual(logs.filter { $0.level == "pass" }.map(\.message), ["bru", "insomnia", "hoppscotch", "thunder", "jetbrains"], logs.map { $0.level + ": " + $0.message }.joined(separator: "\n"))
        XCTAssertEqual(store.environment?.values["fromHopp"], "h"); XCTAssertEqual(store.environment?.values["fromThunder"], "t")
        XCTAssertEqual(store.workspace.globalValues["fromJetBrains"], "application/json")
    }
    func testDigestAnswersChallengeAndGlobalsApplyToTheSameSend() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var digest = APIRequest(name: "Digest", url: "http://127.0.0.1:8766/digest?algorithm={{algorithm}}"); digest.auth.kind = .digest; digest.auth.username = "Mufasa"; digest.auth.password = "{{password}}"
        var wrong = digest; wrong.id = UUID(); wrong.auth.password = "nope"
        var scripted = APIRequest(name: "Globals", url: "http://127.0.0.1:8766/echo?g={{fromScript}}&h={{host}}"); scripted.scriptsEnabled = true
        scripted.preScript = "pm.globals.set('fromScript', 'set-' + pm.globals.get('host'));"
        store.workspace = Workspace(collections: [RequestCollection(name: "Auth", requests: [digest, wrong, scripted])])
        store.workspace.globals = [Field("password", "Circle of Life"), Field("host", "global"), Field("algorithm", "MD5")]
        for algorithm in ["MD5", "SHA-256"] {
            store.workspace.globals![2].value = algorithm
            store.selectedRequestID = digest.id; store.send(); try await wait { store.runningID == nil }
            XCTAssertNil(store.errors[digest.id]); XCTAssertEqual(store.responses[digest.id]?.response.status, 200, algorithm); XCTAssertTrue(store.responses[digest.id]?.response.text.contains("true") == true)
        }
        store.selectedRequestID = wrong.id; store.send(); try await wait { store.runningID == nil }
        XCTAssertEqual(store.responses[wrong.id]?.response.status, 401)
        store.selectedRequestID = scripted.id; store.send(); try await wait { store.runningID == nil }
        let object = try JSONTools.parse(XCTUnwrap(store.responses[scripted.id]?.response.text)) as! [String: Any], query = object["query"] as! [String: [String]]
        XCTAssertEqual(query["g"], ["set-global"]); XCTAssertEqual(query["h"], ["global"])
        XCTAssertEqual(store.workspace.globalValues["fromScript"], "set-global")
    }
    func testCollectionAndLocalVariableScopes() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var request = APIRequest(name: "Scopes", url: "http://127.0.0.1:8766/echo?c={{fromCollection}}&l={{local}}&s={{shadowed}}"); request.scriptsEnabled = true
        request.preScript = "pm.collectionVariables.set('fromCollection', 'c-' + pm.collectionVariables.get('seed')); pm.collectionVariables.set('shadowed', 'collection'); pm.variables.set('local', 'l-' + pm.variables.get('seed'));"
        request.postScript = "pm.test('local visible', () => pm.expect(pm.variables.get('local')).to.equal('l-1')); pm.collectionVariables.unset('seed');"
        var collection = RequestCollection(name: "Vars", requests: [request]); var defaults = RequestDefaults(); defaults.variables = [Field("seed", "1")]; collection.defaults = defaults
        var environment = APIEnvironment(name: "Env", variables: [Field("shadowed", "environment")]); environment.id = UUID()
        store.workspace = Workspace(collections: [collection], environments: [environment]); store.workspace.selectedEnvironmentID = environment.id
        store.selectedRequestID = request.id; store.send(); try await wait { store.runningID == nil }
        XCTAssertNil(store.errors[request.id])
        let object = try JSONTools.parse(XCTUnwrap(store.responses[request.id]?.response.text)) as! [String: Any], query = object["query"] as! [String: [String]]
        XCTAssertEqual(query["c"], ["c-1"]); XCTAssertEqual(query["l"], ["l-1"]); XCTAssertEqual(query["s"], ["environment"])
        XCTAssertEqual(store.responses[request.id]?.response.logs.filter { $0.level == "pass" && $0.message.hasPrefix("local visible") }.count, 1)
        XCTAssertEqual(store.responses[request.id]?.response.logs.filter { $0.level == "fail" }.count, 0)
        let saved = store.workspace.collections[0].defaults?.variables.reduce(into: [String: String]()) { $0[$1.name] = $1.value }
        XCTAssertEqual(saved, ["fromCollection": "c-1", "shadowed": "collection"])
        XCTAssertNil(store.workspace.environments[0].variables.first { $0.name == "local" })
    }
    func testPostmanCookiesExposeResponseCookiesForTheRequestURL() async throws {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var request = APIRequest(name: "Cookies", url: "http://127.0.0.1:8766/set-cookies"); request.scriptsEnabled = true
        request.postScript = """
        pm.test('cookie list', () => {
          pm.expect(pm.cookies.get('session')).to.equal('abc'); pm.expect(pm.cookies.has('theme', 'dark')).to.be.true; pm.expect(pm.cookies.has('scoped')).to.be.false;
          pm.expect(pm.cookies.count()).to.equal(2); pm.expect(pm.cookies.toObject()).to.eql({session: 'abc', theme: 'dark'}); pm.expect(pm.cookies.one('session').httpOnly).to.be.true;
        });
        tests['legacy cookies'] = responseCookies.length === 2 && postman.getResponseCookie('theme').value === 'dark';
        """
        store.workspace = Workspace(collections: [RequestCollection(name: "Cookies", requests: [request])]); store.selectedRequestID = request.id
        store.send(); try await wait { store.runningID == nil }
        XCTAssertNil(store.errors[request.id])
        let logs = try XCTUnwrap(store.responses[request.id]?.response.logs)
        XCTAssertEqual(logs.filter { $0.level == "pass" }.count, 2, "\(logs)"); XCTAssertEqual(logs.filter { $0.level == "fail" || $0.level == "error" }.count, 0, "\(logs)")
    }
    func testRequestTabsOpenCloseAndSelectNeighbours() {
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let requests = (0..<25).map { APIRequest(name: "R\($0)") }
        store.workspace = Workspace(collections: [RequestCollection(name: "Tabs", requests: requests)])
        for index in [0, 1, 2, 1] { store.selectedRequestID = requests[index].id }
        XCTAssertEqual(store.openRequestIDs, requests[0...2].map(\.id))
        store.closeTabs([requests[1].id]); XCTAssertEqual(store.selectedRequestID, requests[2].id); XCTAssertEqual(store.openRequestIDs, [requests[0].id, requests[2].id])
        store.closeTabs([requests[2].id]); XCTAssertEqual(store.selectedRequestID, requests[0].id)
        store.closeTabs([requests[0].id]); XCTAssertNil(store.selectedRequestID); XCTAssertTrue(store.openRequestIDs.isEmpty)
        for request in requests { store.selectedRequestID = request.id }
        XCTAssertEqual(store.openRequestIDs.count, WorkspaceStore.maximumTabs); XCTAssertEqual(store.openRequestIDs.first, requests[5].id)
        store.closeTabs(Set(store.openRequestIDs).subtracting([requests[10].id])); XCTAssertEqual(store.openRequestIDs, [requests[10].id]); XCTAssertEqual(store.selectedRequestID, requests[10].id)
        store.selectedRequestID = requests[11].id; store.closeTabs([requests[10].id]); XCTAssertEqual(store.selectedRequestID, requests[11].id)
    }
    func testRequestTabsRestoreAfterRelaunch() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkspaceStore(directory: directory), requests = (0..<4).map { APIRequest(name: "R\($0)") }
        store.workspace = Workspace(collections: [RequestCollection(name: "Tabs", requests: requests)])
        for index in [2, 0, 3, 1] { store.selectedRequestID = requests[index].id }
        store.workspace.collections[0].requests.removeAll { $0.id == requests[3].id }; store.selectedRequestID = requests[0].id; store.save()
        let relaunched = WorkspaceStore(directory: directory); XCTAssertNil(relaunched.issue)
        XCTAssertEqual(relaunched.openRequestIDs, [requests[2].id, requests[0].id, requests[1].id]); XCTAssertEqual(relaunched.selectedRequestID, requests[0].id)
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

    func testCryptoJSSubsetMatchesReferenceVectors() async throws {
        let script = ##"""
        const m = 'Monkeytail ✓ '.repeat(20), k = 'k'.repeat(200), fox = 'The quick brown fox jumps over the lazy dog';
        const checks = {
          md5: CryptoJS.MD5(m).toString() === 'd85c2b04e692a08e9d4eae4ca5cb45c3', sha1: CryptoJS.SHA1(m).toString() === '8872da04a8301368be81d40e66dffffda95650d3',
          sha256: CryptoJS.SHA256(m).toString() === '105f51e9464ade995b167ea5be5d910672c7f08698e15cbec2565e752044b327', empty: `${CryptoJS.SHA256('')}` === 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          sha512: CryptoJS.SHA512(m).toString(CryptoJS.enc.Hex) === '6d45d172e09c080138490c18aa1b369baeaeb2d93b63285d7b1cd6d39f1189f269200fbc562eae73fef1912bbbfc00dd6584b334890a4aff7bd31ce1b263f909',
          hs256: require('crypto-js/hmac-sha256')(m, k).toString() === '06bb778ad06be5a4b3e0f21ba6c1b0ff592bbce1517b8bc7208811f779c1867b',
          hs512: CryptoJS.enc.Base64.stringify(CryptoJS.HmacSHA512(m, k)) === 'uaTmxgtDLnXl+0R118LxFqePklV1BJllyuFBGC/2jz9vWhyWdxnHtFRKStMM+3eQF2AlLIcOxN7tMspSZpI7Cw==',
          hmd5: CryptoJS.HmacMD5(fox, 'key').toString() === '80070713463e7749b90c2dc24911e275', hsha1: require('crypto-js').HmacSHA1(fox, CryptoJS.enc.Utf8.parse('key')).toString() === 'de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9',
          utf8: CryptoJS.enc.Base64.parse(CryptoJS.enc.Base64.stringify(CryptoJS.enc.Utf8.parse(m))).toString(CryptoJS.enc.Utf8) === m,
          base64url: CryptoJS.enc.Base64url.stringify(CryptoJS.lib.WordArray.create([0xfbffbf00], 3)) === '-_-_', words: CryptoJS.enc.Hex.parse('0102030405').words[1] === 0x05000000,
          random: CryptoJS.lib.WordArray.random(16).sigBytes === 16, uuid: /^[0-9a-f-]{36}$/.test(require('uuid').v4()), btoa: require('btoa')('hi') === 'aGk='
        };
        let missing = ''; try { require('cheerio'); } catch (error) { missing = error.message; }
        console.log(JSON.stringify({failed: Object.keys(checks).filter(key => !checks[key]), missing}));
        """##
        let result = try await ScriptRunner().run(script, request: APIRequest(), variables: [:])
        let line = try XCTUnwrap(result.logs.last?.message), object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["failed"] as? [String], []); XCTAssertTrue((object["missing"] as? String)?.contains("Built-in modules: crypto-js") == true, line)
    }
    func testLodashMomentAndPostmanStyleRedeclarationsRunInTheSandbox() async throws {
        let script = ##"""
        var CryptoJS = require('crypto-js'), moment = require('moment'), lodash = require('lodash');
        const users = [{user: 'fred', age: 40, active: false}, {user: 'barney', age: 36, active: true}];
        const checks = {
          crypto: CryptoJS.SHA256('').toString().startsWith('e3b0c442'), global: _ === lodash && require('lodash/get') === _.get,
          get: _.get({a: [{b: {c: 3}}]}, 'a[0].b.c') === 3, pick: _.isEqual(_.pick({a: 1, b: {c: 2, d: 3}}, ['a', 'b.c']), {a: 1, b: {c: 2}}),
          sortBy: _.sortBy(users, 'age').map(u => u.user).join() === 'barney,fred', chain: _.chain(users).filter('active').map('user').head().value() === 'barney',
          strings: _.camelCase('Foo Bar') === 'fooBar' && _.kebabCase('XMLHttpRequest') === 'xml-http-request', merge: _.merge({a: [{b: 2}]}, {a: [{c: 3}]}).a[0].b === 2,
          format: moment.utc('2026-03-31T13:05:09.045+08:00').format('YYYY-MM-DD HH:mm:ss.SSS dddd Do') === '2026-03-31 05:05:09.045 Tuesday 31st',
          add: moment.utc('2026-01-31').add(1, 'month').format('YYYY-MM-DD') === '2026-02-28', diff: moment.utc('2026-03-31').diff(moment.utc('2026-01-15'), 'days') === 75,
          parse: moment.utc('04/11/2026 3:15 PM', 'DD/MM/YYYY h:mm A').toISOString() === '2026-11-04T15:15:00.000Z', invalid: !moment('2026-13-45', 'YYYY-MM-DD').isValid(),
          iso: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/.test(moment().format()), unix: moment.unix(1700000000).toISOString() === '2023-11-14T22:13:20.000Z'
        };
        pm.environment.set('stamp', moment.utc(0).format('YYYYMMDD'));
        console.log(JSON.stringify(Object.keys(checks).filter(key => !checks[key])));
        """##
        let result = try await ScriptRunner().run(script, request: APIRequest(), variables: [:])
        XCTAssertEqual(result.logs.last?.message, "[]", result.logs.map(\.message).joined(separator: "\n")); XCTAssertEqual(result.variables["stamp"], "19700101")
    }
    func testCryptoJSAESAndKeyDerivationMatchReferenceVectors() async throws {
        let script = ##"""
        const AES = require('crypto-js/aes'), ECB = require('crypto-js/mode-ecb'), m = 'Monkeytail ✓', U = CryptoJS.enc.Utf8;
        const checks = {
          passphrase: AES.encrypt(m, 'secret', {salt: CryptoJS.enc.Hex.parse('0102030405060708')}).toString() === 'U2FsdGVkX18BAgMEBQYHCKYVuZCDAr6sbPJxUdjVkc4=',
          passDecrypt: AES.decrypt('U2FsdGVkX18BAgMEBQYHCKYVuZCDAr6sbPJxUdjVkc4=', 'secret').toString(U) === m,
          randomSalt: CryptoJS.AES.decrypt(CryptoJS.AES.encrypt(m, 'pw').toString(), 'pw').toString(U) === m,
          cbc: CryptoJS.AES.encrypt(m, U.parse('0123456789abcdef0123456789abcdef'), {iv: U.parse('fedcba9876543210')}).toString() === 'e9BY06i1jt3tDJvumuhTCg==',
          cbcDecrypt: CryptoJS.AES.decrypt('e9BY06i1jt3tDJvumuhTCg==', U.parse('0123456789abcdef0123456789abcdef'), {iv: U.parse('fedcba9876543210')}).toString(U) === m,
          ecb: CryptoJS.AES.encrypt(m, U.parse('0123456789abcdef'), {mode: ECB}).ciphertext.toString() === 'bb17fe03906341b3fffb8e521d81e84f',
          ctr: CryptoJS.AES.decrypt(CryptoJS.AES.encrypt(m, U.parse('0123456789abcdef'), {iv: U.parse('fedcba9876543210'), mode: CryptoJS.mode.CTR, padding: CryptoJS.pad.NoPadding}), U.parse('0123456789abcdef'), {iv: U.parse('fedcba9876543210'), mode: CryptoJS.mode.CTR, padding: CryptoJS.pad.NoPadding}).toString(U) === m,
          pbkdf2: CryptoJS.PBKDF2('password', 'salt', {keySize: 8, iterations: 1000}).toString() === '632c2812e46d4604102ba7618e9d6d7d2f8128f6266b4a03264d2a0460b7dcb3',
          sha: CryptoJS.SHA384('abc').toString().startsWith('cb00753f45a35e8b') && CryptoJS.SHA224('abc').toString().startsWith('23097d223405d822'),
          progressive: CryptoJS.algo.SHA256.create().update('a').update('bc').finalize().toString() === CryptoJS.SHA256('abc').toString()
        };
        let missingIV = ''; try { CryptoJS.AES.encrypt(m, U.parse('0123456789abcdef')); } catch (error) { missingIV = error.message; }
        console.log(JSON.stringify({failed: Object.keys(checks).filter(key => !checks[key]), missingIV}));
        """##
        let result = try await ScriptRunner().run(script, request: APIRequest(), variables: [:])
        let line = try XCTUnwrap(result.logs.last?.message), object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(object["failed"] as? [String], [], line); XCTAssertTrue((object["missingIV"] as? String)?.contains("needs a 16-byte iv") == true, line)
    }
    func testUntrustedServerCertificateCanBeTrustedForOneHostAndPort() async throws {
        let request = URLRequest(url: URL(string: "https://localhost:8769/")!)
        var rejected: TrustedCertificate?
        do { _ = try await HTTPClient().send(request); XCTFail("A self-signed certificate must be rejected by default.") } catch let error as UntrustedCertificateError { rejected = error.certificate }
        let certificate = try XCTUnwrap(rejected)
        XCTAssertEqual(certificate.id, "localhost:8769"); XCTAssertEqual(certificate.subject, "Monkeytail Local Test CA"); XCTAssertEqual(certificate.sha256.count, 95)
        let trusted = try await HTTPClient().send(request, trusted: [certificate]); XCTAssertEqual(trusted.status, 200)
        var otherFingerprint = certificate; otherFingerprint.sha256 = String(repeating: "00:", count: 31) + "00"
        var otherHost = certificate; otherHost.host = "127.0.0.1"
        for wrong in [otherFingerprint, otherHost] {
            do { _ = try await HTTPClient().send(request, trusted: [wrong]); XCTFail("Trust must match the exact host, port and fingerprint.") } catch is UntrustedCertificateError {}
        }
        let store = WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), model = APIRequest(url: "https://localhost:8769/")
        store.workspace = Workspace(collections: [RequestCollection(name: "TLS", requests: [model])]); store.selectedRequestID = model.id
        store.send(); try await wait { store.runningID == nil }
        XCTAssertEqual(store.untrustedCertificates[model.id], certificate); XCTAssertNotNil(store.errors[model.id])
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

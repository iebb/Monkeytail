import XCTest
@testable import MonkeytailCore

final class RemoteImportTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock(); private var stored: [URLRequest] = []; private var counts: [String: Int] = [:]
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return stored }
        func add(_ request: URLRequest) -> Int { lock.lock(); defer { lock.unlock() }; stored.append(request); let key = request.url!.absoluteString; counts[key, default: 0] += 1; return counts[key]! }
    }
    private func importer(_ routes: [String: String], recorder: Recorder, statuses: [String: [Int]] = [:]) -> RemoteImporter {
        RemoteImporter(fetch: { request in
            let key = request.url!.absoluteString, call = recorder.add(request)
            let scripted = statuses[key].map { $0[min(call - 1, $0.count - 1)] }
            let status = scripted ?? (routes[key] == nil ? 404 : 200)
            return (Data((routes[key] ?? #"{"error":{"message":"missing"}}"#).utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: status == 429 ? ["Retry-After": "2"] : [:])!)
        }, pause: { _ in })
    }

    func testPostmanSignInReadsTheDesktopRedirect() throws {
        let callback = "https://erisedstraehruoytubecafruoytonwohsi.chromiumapp.org/?user_id=1&team_id=7&name=Ada&access_token=tok%2B1&region="
        let session = try XCTUnwrap(try PostmanSession(callback: URL(string: callback + "us")!))
        XCTAssertEqual(session.accessToken, "tok+1"); XCTAssertEqual(session.teamID, "7"); XCTAssertEqual(session.gateway, "https://bifrost-https-v4.gw.postman.com")
        XCTAssertEqual(try PostmanSession(callback: URL(string: callback + "eu")!)?.gateway, "https://bifrost.gw.eu.postman.com")
        XCTAssertNil(try PostmanSession(callback: URL(string: "https://identity.getpostman.com/client/login?access_token=tok")!))
        XCTAssertThrowsError(try PostmanSession(callback: URL(string: "https://erisedstraehruoytubecafruoytonwohsi.chromiumapp.org/?error=denied")!))
        XCTAssertEqual(PostmanSession.loginURL.absoluteString, "https://auth.postman.com/__redirect/client/login?app_id=erisedstraehruoytubecafruoytonwohsi&__showRegionChooserIfNoneDetected=1&__region=us")
    }

    func testPostmanSignInNoticesWhenGoogleSignInEndsOnTheWebApp() {
        XCTAssertTrue(PostmanSession.isWebApp(URL(string: "https://sg-intl.postman.co/home?utm_referrer=https://accounts.google.co.jp/")!))
        XCTAssertTrue(PostmanSession.isWebApp(URL(string: "https://go.postman.co/")!))
        XCTAssertFalse(PostmanSession.isWebApp(URL(string: "https://identity.getpostman.com/login")!))
        XCTAssertFalse(PostmanSession.isWebApp(URL(string: "https://auth.postman.com/__redirect/client/login")!))
        XCTAssertFalse(PostmanSession.isWebApp(URL(string: "https://www.postman.com/legal/privacy-policy")!))
        XCTAssertFalse(PostmanSession.isWebApp(URL(string: "https://accounts.google.com/o/oauth2/auth")!))
        XCTAssertTrue(PostmanSession.needsBrowser(URL(string: "https://identity.getpostman.com/google/oauth2?authFlowId=1")!))
        XCTAssertTrue(PostmanSession.needsBrowser(URL(string: "https://identity.getpostman.com/oauth2/github/init")!))
        XCTAssertFalse(PostmanSession.needsBrowser(URL(string: "https://identity.getpostman.com/login")!))
    }

    func testPostmanBrowserSignInPollsForTheSessionLikeTheDesktopApp() async throws {
        let identity = "https://identity.getpostman.com", recorder = Recorder()
        let page = #"<script> var authTarget = "login", authVerifier = "ab12", authChallenge = "cd34", authStartPath = "/client-auth/confirm", redirectUri = ""; </script>"#
        let callback = "https://erisedstraehruoytubecafruoytonwohsi.chromiumapp.org/?team_id=7&access_token=tok&region=eu"
        let client = scripted(recorder) { request, _ in
            let polls = recorder.requests.filter { $0.url!.path.hasSuffix("/consume") }.count
            switch request.url!.absoluteString {
            case identity + "/client/browser-auth/init?app_id=erisedstraehruoytubecafruoytonwohsi&target=login": return (200, page, [:])
            case identity + "/handover/preauth/ab12/consume": return (200, polls < 3 ? ["status": "not_authenticated"] : ["status": "authenticated", "redirect": "/handover/done?id=1"], [:])
            case identity + "/handover/done?id=1": return (302, "", ["Location": callback])
            default: return (404, "{}", [:])
            }
        }
        let login = try await client.postmanBrowserLogin()
        XCTAssertEqual(login.url.absoluteString, identity + "/client-auth/confirm?auth_challenge=cd34&auth_device=app_native&auth_device_version=11.68.5")
        let session = try await client.postmanSession(login)
        XCTAssertEqual(session.accessToken, "tok"); XCTAssertEqual(session.teamID, "7"); XCTAssertEqual(session.gateway, "https://bifrost.gw.eu.postman.com")
        XCTAssertEqual(recorder.requests.filter { $0.url!.path.hasSuffix("/consume") }.count, 3)
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.contains("Postman/11.68.5 Electron/") == true })

        let expired = scripted(Recorder()) { _, _ in (404, ["error": ["name": "EntityNotFound"]], [:]) }
        do { _ = try await expired.postmanSession(login); XCTFail("expected an error") } catch { XCTAssertTrue(error.localizedDescription.contains("expired")) }

        let followed = RemoteImporter(fetch: { request in
            if request.url!.path.hasSuffix("/consume") { return (Data(#"{"status":"authenticated","redirect":"/handover/done"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!) }
            throw URLError(.cannotFindHost, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: callback)!])
        }, pause: { _ in })
        let recovered = try await followed.postmanSession(login)
        XCTAssertEqual(recovered.accessToken, "tok")

        let elsewhere = Recorder()
        let direct = scripted(elsewhere) { request, _ -> (Int, Any, [String: String]) in
            guard request.url!.path.hasSuffix("/consume") else { return (500, "{}", [:]) }
            return (200, ["status": "authenticated", "redirect": "https://desktop.handover.invalid/done#access_token=tok2&team_id=9"], [:])
        }
        let handed = try await direct.postmanSession(login)
        XCTAssertEqual(handed.accessToken, "tok2"); XCTAssertEqual(handed.teamID, "9")
        XCTAssertFalse(elsewhere.requests.contains { $0.url!.host == "desktop.handover.invalid" })
    }

    func testPostmanImportsEveryWorkspaceCollectionEnvironmentAndGlobalsFromSync() async throws {
        let gateway = "https://bifrost-https-v4.gw.postman.com", recorder = Recorder()
        let orders: [String: Any] = ["id": "c1", "owner": "1", "name": "Orders", "order": [], "folders_order": ["f1"], "folders": [["id": "f1", "name": "Shipping", "order": ["r1"], "folders_order": []]],
                                     "requests": [["id": "r1", "name": "List", "method": "GET", "url": "{{base}}/orders", "folder": "f1", "dataMode": "params"]]]
        let client = scripted(recorder) { request, body in
            switch (request.url!.absoluteString, body) {
            case (gateway + "/ws/proxy", let body) where body.contains(#"\/workspaces?archived=false""#):
                return (200, ["data": [["id": "w1", "name": "Team", "visibilityStatus": "team"]], "meta": ["nextCursor": "c 2"]], [:])
            case (gateway + "/ws/proxy", let body) where body.contains("cursor=c%202"): return (200, ["data": [["id": "w2", "name": "Mine", "visibilityStatus": "personal"], ["id": "w1", "name": "Team"]], "meta": [:]], [:])
            case (gateway + "/ws/proxy", let body) where body.contains("w2?include=elements"): return (200, ["data": ["elements": ["collections": ["1-c1"], "environments": []]]], [:])
            case (gateway + "/list/collection?workspace=w1", _): return (200, ["data": [["id": "c1", "owner": "1", "name": "Orders"]]], [:])
            case (gateway + "/list/environment?workspace=w1", _): return (200, ["data": [["id": "e1", "owner": "1", "name": "Prod"]]], [:])
            case (gateway + "/list/collection?workspace=w2", _), (gateway + "/list/environment?workspace=w2", _): return (200, ["data": []], [:])
            case (gateway + "/collection/1-c1?populate=true", _): return (200, ["data": orders], [:])
            case (gateway + "/environment/1-e1", _): return (200, ["data": ["id": "e1", "name": "Prod", "values": [["key": "base", "value": "https://api.example.com", "enabled": true]]]], [:])
            case (gateway + "/workspace/w1/globals", _): return (200, ["data": ["values": [["key": "region", "value": "eu", "enabled": true]]]], [:])
            default: return (404, "{}", [:])
            }
        }
        let session = PostmanSession(accessToken: "tok", teamID: "7", region: "us")
        let workspaces = try await client.postmanWorkspaces(session)
        XCTAssertEqual(workspaces, [RemoteWorkspace(id: "w1", name: "Team", kind: "team"), RemoteWorkspace(id: "w2", name: "Mine", kind: "personal")])
        let result = try await client.postman(session, workspaces: workspaces)
        XCTAssertEqual(result.workspace.collections.map(\.name), ["Orders"])
        XCTAssertEqual(result.workspace.collections[0].folders?.map(\.name), ["Shipping"])
        XCTAssertEqual(result.workspace.collections[0].requests.first?.url, "{{base}}/orders"); XCTAssertEqual(result.workspace.collections[0].requests.first?.folderID, result.workspace.collections[0].folders?.first?.id)
        XCTAssertEqual(result.workspace.environments.map(\.name), ["Team / Prod"])
        XCTAssertEqual(result.workspace.environments.first?.values["base"], "https://api.example.com")
        XCTAssertEqual(result.workspace.globalValues["region"], "eu")
        XCTAssertEqual(recorder.requests.filter { $0.url!.path == "/collection/1-c1" }.count, 1)
        XCTAssertTrue(recorder.requests.filter { $0.url!.path.hasPrefix("/list/") || $0.url!.path == "/ws/proxy" }.allSatisfy { $0.httpMethod == "POST" })
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "x-access-token") == "tok" && $0.value(forHTTPHeaderField: "x-entity-team-id") == "7" && $0.value(forHTTPHeaderField: "x-app-version") == "11.68.5" && $0.url!.host == "bifrost-https-v4.gw.postman.com" })
    }

    func testTransportRetriesRateLimitsAndExplainsFailures() async throws {
        let url = "https://bifrost-https-v4.gw.postman.com/ws/proxy", session = PostmanSession(accessToken: "tok", teamID: "0", region: "us")
        let recorder = Recorder()
        let workspaces = try await importer([url: #"{"data":[{"id":"w","name":"Team"}]}"#], recorder: recorder, statuses: [url: [429, 200]]).postmanWorkspaces(session)
        XCTAssertEqual(workspaces.map(\.id), ["w"]); XCTAssertEqual(recorder.requests.count, 2); XCTAssertNil(recorder.requests[0].value(forHTTPHeaderField: "x-entity-team-id"))
        do { _ = try await importer([url: "{}"], recorder: Recorder(), statuses: [url: [401]]).postmanWorkspaces(session); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("rejected the token"), error.localizedDescription) }
        do { _ = try await importer([url: #"{"error":{"name":"authenticationError","message":"User is not authenticated"}}"#], recorder: Recorder(), statuses: [url: [403]]).postmanWorkspaces(session); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error.localizedDescription, "Postman denied access: User is not authenticated") }
    }

    func testGitHubSourceParsing() {
        XCTAssertEqual(GitHubSource("iebb/Monkeytail").map { [$0.owner, $0.repo, $0.ref ?? "-", $0.path] }, ["iebb", "Monkeytail", "-", ""])
        XCTAssertEqual(GitHubSource("https://github.com/iebb/Monkeytail.git/").map { [$0.owner, $0.repo] }, ["iebb", "Monkeytail"])
        XCTAssertEqual(GitHubSource("https://www.github.com/acme/api/tree/main/collections/bruno").map { [$0.ref ?? "-", $0.path] }, ["main", "collections/bruno"])
        XCTAssertEqual(GitHubSource("acme/api@dev")?.ref, "dev")
        XCTAssertNil(GitHubSource("not a repo")); XCTAssertNil(GitHubSource("https://github.com/acme/api/issues"))
    }

    func testGitHubImportsBrunoRootsAndOtherFormatsAndSkipsNoise() async throws {
        let raw = "https://raw.githubusercontent.com/acme/api/main/"
        let bru = """
        meta {
          name: List users
          type: http
          seq: 1
        }

        get {
          url: {{base}}/users
          body: none
          auth: none
        }
        """
        let postman = #"{"info":{"name":"Shop","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[{"name":"Cart","request":{"method":"GET","url":"https://shop.example.com/cart"}}]}"#
        let tree = #"{"truncated":false,"tree":[{"path":"package.json","type":"blob","size":10},{"path":"api/bruno.json","type":"blob","size":40},{"path":"api/Users","type":"tree"},{"path":"api/Users/List users.bru","type":"blob","size":90},{"path":"api/environments/Local.bru","type":"blob","size":30},{"path":"postman/shop.postman_collection.json","type":"blob","size":200},{"path":".github/workflows/ci.yml","type":"blob","size":10},{"path":"node_modules/x/index.json","type":"blob","size":10},{"path":"docs/readme.md","type":"blob","size":10},{"path":"config/settings.json","type":"blob","size":10}]}"#
        let routes = [
            "https://api.github.com/repos/acme/api": #"{"default_branch":"main"}"#,
            "https://api.github.com/repos/acme/api/git/trees/main?recursive=1": tree,
            raw + "api/bruno.json": #"{"version":"1","name":"Acme API","type":"collection"}"#,
            raw + "api/Users/List%20users.bru": bru,
            raw + "api/environments/Local.bru": "vars {\n  base: http://localhost:3000\n}\n",
            raw + "postman/shop.postman_collection.json": postman,
            raw + "config/settings.json": #"{"theme":"dark"}"#
        ]
        let recorder = Recorder()
        let result = try await importer(routes, recorder: recorder).github(try XCTUnwrap(GitHubSource("acme/api")))
        XCTAssertEqual(Set(result.workspace.collections.map(\.name)), ["Acme API", "Shop"])
        let bruno = try XCTUnwrap(result.workspace.collections.first { $0.name == "Acme API" })
        XCTAssertEqual(bruno.folders?.map(\.name), ["Users"]); XCTAssertEqual(bruno.requests.first?.url, "{{base}}/users")
        XCTAssertEqual(result.workspace.environments.first?.values["base"], "http://localhost:3000")
        let fetched = recorder.requests.map { $0.url!.path }
        XCTAssertFalse(fetched.contains { $0.contains("package.json") || $0.contains(".github") || $0.contains("node_modules") || $0.contains("readme") })
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertTrue(result.warnings.contains { $0.contains("settings.json") }, result.warnings.joined(separator: "\n"))

        let privateRoutes = [
            "https://api.github.com/repos/acme/api/git/trees/main?recursive=1": tree,
            "https://api.github.com/repos/acme/api/contents/postman/shop.postman_collection.json?ref=main": postman
        ]
        let privateRecorder = Recorder()
        let scoped = try await importer(privateRoutes, recorder: privateRecorder).github(try XCTUnwrap(GitHubSource("https://github.com/acme/api/tree/main/postman")), token: "ghp_1")
        XCTAssertEqual(scoped.workspace.collections.map(\.name), ["Shop"])
        XCTAssertTrue(privateRecorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_1" && $0.url!.host == "api.github.com" })
        XCTAssertEqual(privateRecorder.requests.last?.value(forHTTPHeaderField: "Accept"), "application/vnd.github.raw+json")
    }

    /// Answers GraphQL by operation (`?name` for Insomnia, the query text for Hoppscotch) and REST by URL.
    private func scripted(_ recorder: Recorder, _ answer: @escaping @Sendable (URLRequest, String) -> (Int, Any, [String: String])) -> RemoteImporter {
        RemoteImporter(fetch: { request in
            _ = recorder.add(request)
            let (status, body, headers) = answer(request, String(decoding: request.httpBody ?? Data(), as: UTF8.self))
            let data = try body as? String ?? String(decoding: JSONSerialization.data(withJSONObject: body), as: UTF8.self)
            return (Data(data.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }, pause: { _ in })
    }

    private func fixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/insomnia-cloud-sync.json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testSealedBoxBlake2bAndPoly1305MatchLibsodium() throws {
        XCTAssertEqual(SyncCrypto.blake2b(Array("abc".utf8), length: 64).map { String(format: "%02x", $0) }.joined(),
                       "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
        let seal = try XCTUnwrap(try fixture()["seal"] as? [String: String]), fixture = try fixture()
        let secret = try XCTUnwrap(Data(base64Encoded: seal["secretKey"]!)), login = try InsomniaLogin(secretKey: secret)
        XCTAssertEqual(login.publicKey.base64EncodedString(), seal["publicKey"])
        let opened = try SyncCrypto.openSealedBox(try XCTUnwrap(Data(base64Encoded: seal["box"]!)), publicKey: login.publicKey, secretKey: secret)
        XCTAssertTrue(String(decoding: opened, as: UTF8.self).hasPrefix(#"{"token":"sess_1","key":""#))
        let long = try SyncCrypto.openSealedBox(try XCTUnwrap(Data(base64Encoded: fixture["longBox"] as! String)), publicKey: login.publicKey, secretKey: secret)
        XCTAssertEqual(String(decoding: long, as: UTF8.self), String(repeating: "x", count: 200) + "é done")
        var tampered = try XCTUnwrap(Data(base64Encoded: seal["box"]!)); tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try SyncCrypto.openSealedBox(tampered, publicKey: login.publicKey, secretKey: secret))
        XCTAssertTrue(InsomniaLogin().url.absoluteString.hasPrefix("https://app.insomnia.rest/app/auth-app/?loginKey="))
        XCTAssertTrue(login.url.absoluteString.hasSuffix("&source_origin=desktop_app")); XCTAssertFalse(login.url.absoluteString.contains("="  + "="))
    }

    func testInsomniaCloudSyncSignsInLikeTheDesktopAppAndDecryptsTheLatestSnapshot() async throws {
        let fixture = try fixture(), seal = try XCTUnwrap(fixture["seal"] as? [String: String]), recorder = Recorder()
        let blobs = try XCTUnwrap(fixture["blobs"] as? [[String: Any]])
        let client = scripted(recorder) { request, body in
            let url = request.url!.absoluteString
            switch url {
            case "https://api.insomnia.rest/v3/users/me/encryption-keys": return (200, fixture["keys"]!, ["Content-Type": "application/json"])
            case "https://api.insomnia.rest/v3/users/me/spaces?page%5Bsize%5D=200":
                return (200, ["data": [["id": "org_1", "name": "personal", "display_name": "Personal"]], "meta": ["page": ["next": "/v3/users/me/spaces?page[size]=200&page[after]=org_1"]]], [:])
            case "https://api.insomnia.rest/v3/users/me/spaces?page%5Bsize%5D=200&page%5Bafter%5D=org_1": return (200, ["data": [], "meta": ["page": [:]]], [:])
            case "https://api.insomnia.rest/graphql?projects":
                return body.contains("org_1") ? (200, ["data": ["projects": [["id": "proj_1", "name": "Orders API"]]]], [:]) : (500, "{}", [:])
            case "https://api.insomnia.rest/graphql?projectKey": return (200, ["data": ["projectKey": ["encSymmetricKey": fixture["projectKey"]!]]], [:])
            case "https://api.insomnia.rest/graphql?branch": return (200, ["data": ["branch": ["snapshots": ["snap_old", "snap_head"]]]], [:])
            case "https://api.insomnia.rest/graphql?snapshots":
                return body.contains("snap_head") && !body.contains("snap_old") ? (200, ["data": ["snapshots": [["id": "snap_head", "state": blobs.map { ["blob": $0["id"]!, "key": $0["id"]!, "name": ""] }]]]], [:]) : (500, "{}", [:])
            case "https://api.insomnia.rest/graphql?blobs": return (200, ["data": ["blobs": blobs]], [:])
            default: return (404, "{}", [:])
            }
        }
        let login = try InsomniaLogin(secretKey: try XCTUnwrap(Data(base64Encoded: seal["secretKey"]!)))
        let session = try await client.insomniaSignIn(login, code: "  insomnia://app/auth/finish?box=" + seal["box"]!.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + " ")
        let projects = try await client.insomniaProjects(session)
        XCTAssertEqual(projects, [RemoteWorkspace(id: "proj_1", name: "Orders API", kind: "Personal")])
        let encoded = seal["box"]!.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let pasted = try await client.insomniaSignIn(login, code: String(encoded.prefix(40)) + "\n" + String(encoded.dropFirst(40)))
        XCTAssertEqual(pasted.id, "sess_1")
        let result = try await client.insomnia(session, projects: projects)
        let collection = try XCTUnwrap(result.workspace.collections.first)
        XCTAssertEqual(collection.name, "Orders API"); XCTAssertEqual(collection.folders?.map(\.name), ["Shipping"])
        XCTAssertEqual(collection.requests.map(\.url), ["{{base}}/orders"]); XCTAssertEqual(collection.requests.first?.folderID, collection.folders?.first?.id)
        XCTAssertEqual(collection.defaults?.variables.first { $0.name == "base" }?.value, "https://api.example.com")
        XCTAssertEqual(result.workspace.environments.map(\.name), ["Prod"]); XCTAssertEqual(result.workspace.environments.first?.values["token"], "prod-token")
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Session-Id") == "sess_1" && $0.value(forHTTPHeaderField: "X-Insomnia-Client") == "production::darwin::13.3.1" && $0.url!.host == "api.insomnia.rest" })
        XCTAssertTrue(recorder.requests.filter { $0.url!.path == "/graphql" }.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Content-Type") == "application/json" })

        do { _ = try await client.insomniaSignIn(InsomniaLogin(), code: seal["box"]!); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("invalid or expired"), error.localizedDescription) }
    }

    func testHoppscotchMagicLinkSignInImportsPersonalTeamAndGlobalData() async throws {
        let request: [String: Any] = ["v": "11", "name": "List", "method": "GET", "endpoint": "<<base>>/users", "params": [], "headers": [], "auth": ["authType": "inherit", "authActive": true], "body": ["contentType": NSNull(), "body": NSNull()], "preRequestScript": "", "testScript": "", "id": "r1"]
        let personal: [[String: Any]] = [["id": "c1", "name": "Personal API", "folders": [["id": "f1", "name": "Users", "folders": [], "requests": [request], "data": "null"]], "requests": [],
                                          "data": #"{"auth":{"authType":"bearer","authActive":true,"token":"<<token>>"},"headers":[{"key":"X-Team","value":"core","active":true}]}"#]]
        let team: [[String: Any]] = [["id": "c2", "name": "Team API", "folders": [], "requests": [request], "data": "{}"]]
        let exported = String(decoding: try JSONSerialization.data(withJSONObject: personal), as: UTF8.self), teamExported = String(decoding: try JSONSerialization.data(withJSONObject: team), as: UTF8.self)
        let recorder = Recorder()
        let client = scripted(recorder) { request, body in
            switch request.url!.absoluteString {
            case "https://hopp.example.com/backend/v1/auth/signin?origin=desktop": return body.contains("me@example.com") ? (201, ["deviceIdentifier": "dev_1"], [:]) : (400, "{}", [:])
            case "https://hopp.example.com/backend/v1/auth/verify":
                return body.contains("tok_1") && body.contains("dev_1") ? (200, "", ["Set-Cookie": "access_token=at_1; Path=/; HttpOnly, refresh_token=rt_1; Path=/; HttpOnly"]) : (401, "{}", [:])
            case "https://hopp.example.com/backend/graphql":
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer at_1" else { return (401, "{}", [:]) }
                if body.contains("exportUserCollectionsToJSON") { return (200, ["data": ["exportUserCollectionsToJSON": ["exportedCollection": exported], "me": ["environments": [["name": "Local", "variables": #"[{"key":"base","initialValue":"http://localhost","currentValue":"http://localhost","secret":false}]"#]]]]], [:]) }
                if body.contains("globalEnvironments") { return (200, ["data": ["me": ["globalEnvironments": ["variables": #"[{"key":"region","initialValue":"eu","secret":false}]"#]]]], [:]) }
                if body.contains("myTeams") { return (200, ["data": ["myTeams": body.contains("t1") ? [] : [["id": "t1", "name": "Core"]]]], [:]) }
                if body.contains("exportCollectionsToJSON") { return (200, ["data": ["exportCollectionsToJSON": teamExported, "team": ["teamEnvironments": [["name": "Staging", "variables": #"[{"key":"base","value":"https://staging.example.com"}]"#]]]]], [:]) }
                return (400, "{}", [:])
            default: return (404, "{}", [:])
            }
        }
        let server = " https://hopp.example.com/backend/v1/ "
        let pending = try await client.hoppscotchSendLink(server: server, email: " me@example.com ")
        XCTAssertEqual(pending.deviceIdentifier, "dev_1")
        let session = try await client.hoppscotchSignIn(pending, link: "https://hoppscotch.example.com/enter?token=tok_1")
        let result = try await client.hoppscotch(session)
        XCTAssertEqual(result.workspace.collections.map(\.name), ["Personal API", "Team API"])
        let imported = result.workspace.collections[0]
        XCTAssertEqual(imported.folders?.map(\.name), ["Users"]); XCTAssertEqual(imported.requests.first?.url, "{{base}}/users")
        XCTAssertEqual(imported.requests.first?.folderID, imported.folders?.first?.id)
        XCTAssertEqual(imported.defaults?.auth.kind, .bearer); XCTAssertEqual(imported.defaults?.headers.first?.name, "X-Team")
        XCTAssertEqual(result.workspace.environments.map(\.name), ["Local", "Core / Staging"])
        XCTAssertEqual(result.workspace.environments.last?.values["base"], "https://staging.example.com")
        XCTAssertEqual(result.workspace.globalValues["region"], "eu")
        XCTAssertEqual(recorder.requests.first?.httpMethod, "POST")

        do { _ = try await client.hoppscotchSignIn(pending, link: "https://hoppscotch.example.com/enter?token=wrong"); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("invalid or expired"), error.localizedDescription) }
    }

    func testHoppscotchCloudSignsInWithFirebaseEmailLinkLikeTheWebApp() async throws {
        let recorder = Recorder(), firebase = "https://identitytoolkit.googleapis.com/v1/accounts:"
        let client = scripted(recorder) { request, body in
            switch request.url!.absoluteString {
            case firebase + "sendOobCode?key=" + RemoteImporter.hoppscotchFirebaseKey:
                return body.contains(#""requestType":"EMAIL_SIGNIN""#) && body.contains("me@example.com") ? (200, ["email": "me@example.com"], [:]) : (400, "{}", [:])
            case firebase + "signInWithEmailLink?key=" + RemoteImporter.hoppscotchFirebaseKey:
                return body.contains("oob_1") && body.contains("me@example.com") ? (200, ["idToken": "id_1", "refreshToken": "r"], [:]) : (400, ["error": ["message": "INVALID_OOB_CODE"]], [:])
            case "https://api.hoppscotch.io/graphql":
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer id_1" else { return (401, "{}", [:]) }
                if body.contains("exportUserCollectionsToJSON") { return (200, ["data": ["exportUserCollectionsToJSON": ["exportedCollection": #"[{"id":"c1","name":"Mine","folders":[],"requests":[],"data":"{}"}]"#], "me": ["environments": []]]], [:]) }
                if body.contains("globalEnvironments") { return (200, ["errors": [["message": "user_environment/global_env_does_not_exists"]]], [:]) }
                return (200, ["data": ["myTeams": []]], [:])
            default: return (404, "{}", [:])
            }
        }
        let pending = try await client.hoppscotchSendLink(email: "me@example.com")
        XCTAssertNil(pending.deviceIdentifier)
        let link = "https://postwoman-api.firebaseapp.com/__/auth/links?link=" + "https://postwoman-api.firebaseapp.com/__/auth/action?apiKey=k&mode=signIn&oobCode=oob_1&continueUrl=https://hoppscotch.io/enter".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let session = try await client.hoppscotchSignIn(pending, link: link)
        let result = try await client.hoppscotch(session)
        XCTAssertEqual(result.workspace.collections.map(\.name), ["Mine"])
        XCTAssertTrue(recorder.requests.filter { $0.url!.host == "identitytoolkit.googleapis.com" }.allSatisfy { $0.value(forHTTPHeaderField: "Referer") == "https://hoppscotch.io/" })
        do { _ = try await client.hoppscotchSignIn(pending, link: "https://hoppscotch.io/enter?oobCode=stale"); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("invalid or expired"), error.localizedDescription) }
    }
}

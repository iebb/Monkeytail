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

    func testPostmanImportsEveryWorkspaceCollectionEnvironmentAndGlobals() async throws {
        let host = "https://api.getpostman.com"
        let routes = [
            host + "/workspaces": #"{"workspaces":[{"id":"w1","name":"Team","type":"team"},{"id":"w2","name":"Mine","type":"personal"}]}"#,
            host + "/workspaces/w1": #"{"workspace":{"id":"w1","collections":[{"id":"c1","uid":"1-c1","name":"Orders"}],"environments":[{"id":"e1","uid":"1-e1","name":"Prod"}]}}"#,
            host + "/workspaces/w2": #"{"workspace":{"id":"w2","collections":[{"id":"c1","uid":"1-c1","name":"Orders"}]}}"#,
            host + "/collections/1-c1": #"{"collection":{"info":{"name":"Orders","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[{"name":"Shipping","item":[{"name":"List","request":{"method":"GET","url":"{{base}}/orders"}}]}]}}"#,
            host + "/environments/1-e1": #"{"environment":{"name":"Prod","values":[{"key":"base","value":"https://api.example.com","enabled":true}]}}"#,
            host + "/workspaces/w1/global-variables": #"{"values":[{"key":"region","value":"eu","enabled":true}]}"#
        ]
        let recorder = Recorder(), client = importer(routes, recorder: recorder)
        let workspaces = try await client.postmanWorkspaces(apiKey: " PMAK-1 ")
        XCTAssertEqual(workspaces.map(\.name), ["Team", "Mine"])
        let result = try await client.postman(apiKey: "PMAK-1", workspaces: workspaces)
        XCTAssertEqual(result.workspace.collections.map(\.name), ["Orders"])
        XCTAssertEqual(result.workspace.collections[0].folders?.map(\.name), ["Shipping"])
        XCTAssertEqual(result.workspace.collections[0].requests.first?.url, "{{base}}/orders")
        XCTAssertEqual(result.workspace.environments.map(\.name), ["Team / Prod"])
        XCTAssertEqual(result.workspace.environments.first?.values["base"], "https://api.example.com")
        XCTAssertEqual(result.workspace.globalValues["region"], "eu")
        XCTAssertEqual(recorder.requests.filter { $0.url!.absoluteString.hasSuffix("/collections/1-c1") }.count, 1)
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Api-Key") == "PMAK-1" && $0.url!.host == "api.getpostman.com" })
    }

    func testTransportRetriesRateLimitsAndExplainsFailures() async throws {
        let url = "https://api.getpostman.com/workspaces"
        let recorder = Recorder()
        let workspaces = try await importer([url: #"{"workspaces":[{"id":"w","name":"Team"}]}"#], recorder: recorder, statuses: [url: [429, 200]]).postmanWorkspaces(apiKey: "k")
        XCTAssertEqual(workspaces.map(\.id), ["w"]); XCTAssertEqual(recorder.requests.count, 2)
        do { _ = try await importer([url: "{}"], recorder: Recorder(), statuses: [url: [401]]).postmanWorkspaces(apiKey: "bad"); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("rejected the token"), error.localizedDescription) }
        do { _ = try await importer([:], recorder: Recorder()).postmanWorkspaces(apiKey: "  "); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error.localizedDescription, "Enter a Postman API key.") }
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

    func testHoppscotchTeamCollectionAndEnvironmentByID() async throws {
        let base = "https://hopp.example.com/backend/v1/access-tokens/"
        let collection = #"{"id":"col1","title":"Team API","parentID":null,"data":"{\"auth\":{\"authType\":\"bearer\",\"authActive\":true,\"token\":\"<<token>>\"},\"headers\":[{\"key\":\"X-Team\",\"value\":\"core\",\"active\":true}]}","folders":[{"id":"f1","title":"Users","data":null,"parentID":"col1","folders":[],"requests":[{"id":"r1","title":"List","request":"{\"v\":\"11\",\"name\":\"List\",\"method\":\"GET\",\"endpoint\":\"<<base>>/users\",\"params\":[],\"headers\":[],\"auth\":{\"authType\":\"inherit\",\"authActive\":true},\"body\":{\"contentType\":null,\"body\":null},\"preRequestScript\":\"\",\"testScript\":\"\"}"}]}],"requests":[]}"#
        let routes = [base + "collection/col1": collection, base + "environment/env1": #"{"id":"env1","teamID":"t","name":"Staging","variables":[{"key":"base","value":"https://staging.example.com","secret":false}]}"#]
        let recorder = Recorder()
        let result = try await importer(routes, recorder: recorder).hoppscotch(server: "https://hopp.example.com/backend", token: "pat_1", collectionIDs: ["col1"], environmentIDs: ["env1"])
        let imported = try XCTUnwrap(result.workspace.collections.first)
        XCTAssertEqual(imported.name, "Team API"); XCTAssertEqual(imported.folders?.map(\.name), ["Users"])
        XCTAssertEqual(imported.requests.first?.url, "{{base}}/users"); XCTAssertEqual(imported.requests.first?.folderID, imported.folders?.first?.id)
        XCTAssertEqual(imported.defaults?.auth.kind, .bearer); XCTAssertEqual(imported.defaults?.headers.first?.name, "X-Team")
        XCTAssertEqual(result.workspace.environments.first?.values["base"], "https://staging.example.com")
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer pat_1" })
    }
}

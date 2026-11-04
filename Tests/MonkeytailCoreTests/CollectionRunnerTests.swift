import XCTest
@testable import MonkeytailCore

final class CollectionRunnerTests: XCTestCase {
    func testDynamicVariablesResolvePerOccurrenceAndExplicitValuesWin() throws {
        let ids = try RequestBuilder.resolve("{{$guid}} {{ $guid }}", variables: [:]).split(separator: " ")
        XCTAssertEqual(ids.count, 2); XCTAssertNotEqual(ids[0], ids[1]); XCTAssertNotNil(UUID(uuidString: String(ids[0])))
        XCTAssertNotNil(Int(try RequestBuilder.resolve("{{$timestamp}}", variables: [:])))
        XCTAssertEqual(try RequestBuilder.resolve("{{$randomInt}}", variables: ["$randomInt": "7"]), "7")
        XCTAssertThrowsError(try RequestBuilder.resolve("{{$notReal}}", variables: [:])) { XCTAssertTrue($0.localizedDescription.contains("dynamic")) }
        for name in DynamicVariables.names { XCTAssertNotNil(DynamicVariables.value(name), name) }
        let built = try RequestBuilder.build(APIRequest(url: "https://example.com/{{$randomInt}}"))
        XCTAssertNotNil(Int(built.url!.lastPathComponent))
    }
    func testCSVDataHandlesQuotesNewlinesBOMAndShortRows() throws {
        let csv = "\u{FEFF}name,note,count\r\nAda,\"Hello, \"\"world\"\"\",1\r\n\"Grace\",\"two\nlines\"\r\nLinus,,3\n\n"
        let rows = try RunnerData.parse(Data(csv.utf8), filename: "users.csv")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["name": "Ada", "note": "Hello, \"world\"", "count": "1"])
        XCTAssertEqual(rows[1], ["name": "Grace", "note": "two\nlines", "count": ""])
        XCTAssertEqual(rows[2]["note"], "")
        XCTAssertThrowsError(try RunnerData.parse(Data("a,b\n1,2,3".utf8)))
        XCTAssertThrowsError(try RunnerData.parse(Data("a,a\n1,2".utf8)))
        XCTAssertThrowsError(try RunnerData.parse(Data("a\n\"open".utf8)))
        XCTAssertThrowsError(try RunnerData.parse(Data("a\n".utf8)))
    }
    func testJSONDataStringifiesValues() throws {
        let rows = try RunnerData.parse(Data(#"[{"id":1,"ok":true,"name":"x","tags":["a"],"none":null}]"#.utf8))
        XCTAssertEqual(rows, [["id": "1", "ok": "true", "name": "x", "tags": "[\"a\"]", "none": ""]])
        XCTAssertThrowsError(try RunnerData.parse(Data(#"[1]"#.utf8), filename: "data.json"))
        XCTAssertThrowsError(try RunnerData.parse(Data(#"{"id":1}"#.utf8), filename: "data.json"))
    }
    func testPlanFollowsSidebarOrderAndSkipsStreams() {
        var parent = RequestFolder(name: "Parent"), child = RequestFolder(name: "Child")
        child.parentID = parent.id
        let root = APIRequest(name: "root")
        var b = APIRequest(name: "in parent"), c = APIRequest(name: "in child"), socket = APIRequest(name: "socket")
        b.folderID = parent.id; c.folderID = child.id; socket.transport = .websocket
        var collection = RequestCollection(name: "C", requests: [root, b, socket, c])
        collection.folders = [parent, child]
        XCTAssertEqual(RunnerPlan.requests(in: collection).map(\.name), ["in child", "in parent", "root"])
        XCTAssertEqual(RunnerPlan.requests(in: collection, folderID: parent.id).map(\.name), ["in child", "in parent"])
        parent.parentID = child.id; collection.folders = [parent, child]
        XCTAssertEqual(RunnerPlan.requests(in: collection, folderID: parent.id).map(\.name), ["in child", "in parent"])
    }
    func testPathVariablesSubstituteSegmentsAndRoundTripThroughPostman() throws {
        XCTAssertEqual(RequestBuilder.pathVariableNames(in: "{{base}}/users/:id/posts/:postId?x=:no#:frag"), ["id", "postId"])
        XCTAssertEqual(RequestBuilder.pathVariableNames(in: "http://localhost:8080/:id/:id"), ["id"])
        var request = APIRequest(url: "https://example.com/users/:id/files/:name/:missing")
        request.pathVariables = [Field("id", "{{user}}"), Field("name", "a b/c"), Field("unused", "x", enabled: false)]
        let built = try RequestBuilder.build(request, variables: ["user": "42"])
        XCTAssertEqual(built.url?.absoluteString, "https://example.com/users/42/files/a%20b%2Fc/:missing")
        let exported = try CollectionCodec.encode(Workspace(collections: [RequestCollection(name: "Paths", requests: [request])]), format: .postman)
        let imported = try CollectionCodec.decode(exported).workspace.collections[0].requests[0]
        XCTAssertEqual(imported.pathVariables?.map(\.name), ["id", "name", "unused"])
        XCTAssertEqual(imported.pathVariables?.map(\.enabled), [true, true, false])
    }
    func testNextRequestDirectives() {
        let plan = [APIRequest(name: "Login"), APIRequest(name: "List"), APIRequest(name: "Logout")]
        XCTAssertEqual(RunnerPlan.nextIndex(after: 0, directive: nil, plan: plan), 1)
        XCTAssertNil(RunnerPlan.nextIndex(after: 2, directive: nil, plan: plan))
        XCTAssertNil(RunnerPlan.nextIndex(after: 0, directive: .stop, plan: plan))
        XCTAssertEqual(RunnerPlan.nextIndex(after: 2, directive: .jump("List"), plan: plan), 1)
        XCTAssertEqual(RunnerPlan.nextIndex(after: 0, directive: .jump(plan[2].id.uuidString.lowercased()), plan: plan), 2)
        XCTAssertNil(RunnerPlan.nextIndex(after: 0, directive: .jump("Missing"), plan: plan))
    }
    func testReportsSummariseAndEscapeJUnitAndOmitBodies() throws {
        var report = RunnerReport(name: "API <v1>", environment: "Dev", iterations: 1)
        var ok = RunnerResult(iteration: 1, request: APIRequest(name: "Get & check"))
        ok.status = 200; ok.duration = 0.25; ok.tests = [RunnerTest(name: "Status \"ok\"", passed: true), RunnerTest(name: "Has id", passed: false)]
        ok.bodyPreview = "secret-body"
        var failed = RunnerResult(iteration: 1, request: APIRequest(name: "Broken")); failed.error = "Timed out"
        var skipped = RunnerResult(iteration: 1, request: APIRequest(name: "Skip")); skipped.skipped = true
        report.results = [ok, failed, skipped]
        XCTAssertEqual(report.sentCount, 2); XCTAssertEqual(report.failedCount, 2); XCTAssertEqual(report.testCount, 2); XCTAssertEqual(report.failedTestCount, 1)
        let json = String(decoding: try RunnerReportCodec.encode(report, format: .json), as: UTF8.self)
        XCTAssertFalse(json.contains("secret-body")); XCTAssertTrue(json.contains("\"Broken\""))
        let xml = String(decoding: try RunnerReportCodec.encode(report, format: .junit), as: UTF8.self)
        XCTAssertTrue(xml.contains("name=\"API &lt;v1&gt;\" tests=\"3\" failures=\"1\" errors=\"1\""))
        XCTAssertTrue(xml.contains("Get &amp; check")); XCTAssertTrue(xml.contains("Status &quot;ok&quot;"))
        XCTAssertTrue(xml.contains("<error message=\"Timed out\"/>")); XCTAssertTrue(xml.contains("<skipped/>"))
        XCTAssertNotNil(try? XMLDocument(data: Data(xml.utf8)))
    }
}

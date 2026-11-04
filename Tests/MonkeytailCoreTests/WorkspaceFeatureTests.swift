import XCTest
@testable import MonkeytailCore

final class WorkspaceFeatureTests: XCTestCase {
    func testVariableHintsFindReferencesAndCompleteTrailingBraces() {
        let variables = ["base_url": "https://api.example.com", "token": "t", "user.id": "7"]
        let references = VariableHints.references(in: "{{base_url}}/users/{{ user.id }}?q={{missing}}&id={{$guid}}&again={{base_url}}", variables: variables)
        XCTAssertEqual(references.map(\.name), ["base_url", "user.id", "missing", "$guid"])
        XCTAssertEqual(references.map(\.isResolved), [true, true, false, true])
        XCTAssertFalse(VariableHints.Reference(name: "$nope").isResolved)
        XCTAssertEqual(VariableHints.pendingName(in: "https://x/{{ba"), "ba"); XCTAssertEqual(VariableHints.pendingName(in: "{{"), "")
        XCTAssertNil(VariableHints.pendingName(in: "{{base_url}}/x")); XCTAssertNil(VariableHints.pendingName(in: "{{a b"))
        XCTAssertEqual(VariableHints.suggestions(for: "", variables: variables).prefix(3), ["base_url", "token", "user.id"])
        XCTAssertEqual(VariableHints.suggestions(for: "id", variables: variables).first, "user.id")
        XCTAssertEqual(VariableHints.suggestions(for: "$rand", variables: variables, limit: 2), ["$randomUUID", "$randomInt"])
        XCTAssertEqual(VariableHints.complete("https://x/{{ ba", with: "base_url"), "https://x/{{base_url}}")
        XCTAssertEqual(VariableHints.complete("no braces", with: "base_url"), "no braces")
    }
    func testMultipartIncludesBinaryBytesAndEscapedName() throws {
        var request = APIRequest(method: "POST", url: "https://example.com")
        request.bodyKind = .multipart
        let bytes = Data([0, 255, 13, 10, 1])
        request.multipart = [MultipartPart(name: "greeting", value: "{{message}}"), MultipartPart(name: "f\"ile", file: RequestFile(filename: "test.bin", data: bytes)), MultipartPart(name: "disabled", enabled: false)]
        request.headers = [Field("Content-Type", "multipart/form-data; boundary=stale")]
        let built = try RequestBuilder.build(request, variables: ["message": "hello"])
        let body = try XCTUnwrap(built.httpBody)
        let type = try XCTUnwrap(built.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try XCTUnwrap(type.components(separatedBy: "boundary=").last)
        XCTAssertTrue(body.starts(with: Data("--\(boundary)\r\n".utf8)))
        XCTAssertNotNil(body.range(of: bytes))
        XCTAssertNotNil(body.range(of: Data("name=\"f\\\"ile\"".utf8)))
        XCTAssertNotNil(body.range(of: Data("\r\n\r\nhello\r\n".utf8)))
        XCTAssertNil(body.range(of: Data("disabled".utf8)))
        XCTAssertTrue(body.suffix(boundary.utf8.count + 6).elementsEqual(Data("--\(boundary)--\r\n".utf8)))
    }
    func testImportedFilesNeverReadHostPathsAndRequirePicker() throws {
        let request = try CurlCodec.decode("curl https://example.com -F 'upload=@/etc/passwd;type=text/plain' --form-string 'literal=@not-a-file'").request
        XCTAssertEqual(request.method, "POST"); XCTAssertEqual(request.bodyKind, .multipart)
        XCTAssertNil(request.multipart?[0].file?.data)
        XCTAssertEqual(request.multipart?[1].value, "@not-a-file")
        XCTAssertThrowsError(try RequestBuilder.build(request))
        let exported = try CurlCodec.encode(request)
        XCTAssertEqual(try CurlCodec.decode(exported).request.multipart?.map(\.name), ["upload", "literal"])
        let file = try CurlCodec.decode("curl https://example.com --data-binary @sample.bin").request
        XCTAssertEqual(file.bodyKind, .file); XCTAssertNil(file.fileBody?.data)
        XCTAssertThrowsError(try RequestBuilder.build(file))
    }
    func testFilesSurviveNativeExportAndExternalMetadataRoundTrips() throws {
        var request = APIRequest(method: "POST")
        request.bodyKind = .multipart; request.multipart = [MultipartPart(name: "image", file: RequestFile(filename: "image.png", mimeType: "image/png", data: Data([1,2,3])))]
        let workspace = Workspace(collections: [RequestCollection(name: "Files", requests: [request])])
        for format in ExportFormat.allCases {
            let imported = try CollectionCodec.decode(CollectionCodec.encode(workspace, format: format)).workspace.collections[0].requests[0]
            XCTAssertEqual(imported.bodyKind, .multipart); XCTAssertEqual(imported.multipart?[0].file?.filename, "image.png")
            XCTAssertEqual(imported.multipart?[0].file?.mimeType, "image/png")
            XCTAssertEqual(imported.multipart?[0].file?.data, format == .native ? Data([1,2,3]) : nil)
        }
    }
    func testMultipartRejectsHeaderInjectionAndMissingFiles() throws {
        XCTAssertThrowsError(try MultipartEncoder.encode([MultipartPart(name: "a\r\nInjected: true")], boundary: "test", variables: [:]))
        XCTAssertThrowsError(try MultipartEncoder.encode([MultipartPart(name: "file", file: RequestFile(filename: "missing"))], boundary: "test", variables: [:]))
    }
    func testSyncStripsSecretsAndFilesAndRestoresLocalValues() throws {
        var workspace = Workspace.starter
        workspace.collections[0].requests[0].auth.kind = .bearer
        workspace.collections[0].requests[0].auth.token = "private-token"
        workspace.collections[0].requests[0].headers += [Field("Authorization", "private-header")]
        workspace.collections[0].requests[0].fileBody = RequestFile(filename: "data.bin", data: Data([1,2,3]))
        workspace.environments[0].variables += [Field("api_key", "private-key")]
        var state = WorkspaceSyncState(); try state.capture(workspace)
        let encoded = try JSONEncoder().encode(state)
        let string = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(string.contains("private-token")); XCTAssertFalse(string.contains("private-header")); XCTAssertFalse(string.contains("private-key"))
        let remote = try state.workspace(local: Workspace())
        XCTAssertEqual(remote.collections[0].requests[0].auth.token, "")
        XCTAssertNil(remote.collections[0].requests[0].fileBody?.data)
        let restored = try state.workspace(local: workspace)
        XCTAssertEqual(restored.collections[0].requests[0].auth.token, "private-token")
        XCTAssertEqual(restored.environments[0].values["api_key"], "private-key")
        XCTAssertEqual(restored.collections[0].requests[0].fileBody?.data, Data([1,2,3]))
    }
    func testLegacyCredentialsAndURLSecretsMigrateWithoutChangingEncoding() throws {
        var request = APIRequest(url: "https://example.com/a?q=a%2Bb&token=private%2Bvalue")
        request.auth.token = "old-token"
        let workspace = Workspace(collections: [RequestCollection(name: "Legacy", requests: [request])])
        XCTAssertEqual(SecretPolicy.restore(workspace, secrets: [:]), workspace)
        var secrets: [String: String] = [:]
        let clean = SecretPolicy.strip(workspace, secrets: &secrets, files: true)
        XCTAssertEqual(clean.collections[0].requests[0].url, "https://example.com/a?q=a%2Bb&token=")
        XCTAssertEqual(SecretPolicy.restore(clean, secrets: secrets).collections[0].requests[0].url, request.url)
        var state = WorkspaceSyncState(); try state.capture(.starter)
        let sync = try state.workspace(local: .starter)
        XCTAssertTrue(sync.collections[0].requests[0].url.contains("{{base_url}}"))
    }
    func testCopiedFieldsKeepIndependentLocalSecrets() {
        let field = Field("X-API-Key", "first")
        var first = APIRequest(), second = APIRequest()
        first.headers = [field]; second.headers = [field]; second.headers[0].value = "second"
        let source = Workspace(collections: [RequestCollection(name: "Copies", requests: [first, second])])
        var secrets: [String: String] = [:]
        let clean = SecretPolicy.strip(source, secrets: &secrets, files: false)
        let restored = SecretPolicy.restore(clean, secrets: secrets)
        XCTAssertEqual(restored.collections[0].requests.map { $0.headers[0].value }, ["first", "second"])
    }
    func testSyncConcurrentEditsAndDeleteTombstoneConverge() throws {
        var base = Workspace.starter, first = WorkspaceSyncState()
        let now = Date(); try first.capture(base, now: now)
        var second = WorkspaceSyncState(); second.merge(first)
        var deviceA = base, deviceB = base
        deviceA.collections[0].requests[0].name = "A"
        deviceB.collections[0].requests[1].name = "B"
        try first.capture(deviceA, now: now.addingTimeInterval(1))
        try second.capture(deviceB, now: now.addingTimeInterval(2))
        first.merge(second); second.merge(first)
        XCTAssertEqual(first.records, second.records)
        base = try first.workspace(local: base)
        XCTAssertEqual(base.collections[0].requests[0].name, "A"); XCTAssertEqual(base.collections[0].requests[1].name, "B")
        base.collections[0].requests.removeFirst()
        try first.capture(base, now: now.addingTimeInterval(3)); second.merge(first)
        XCTAssertEqual(try second.workspace(local: base).collections[0].requests.count, 2)
        second.merge(WorkspaceSyncState())
        XCTAssertEqual(try second.workspace(local: base).collections[0].requests.count, 2)
    }
    func testJSONPathKeysIndicesWildcardsAndFailures() throws {
        let data = Data(#"{"data":{"a.b":[{"id":1},{"id":2}],"null":null}}"#.utf8)
        XCTAssertEqual(try JSONPath.extract("$.data['a.b'][1].id", from: data), "2")
        let results = try JSONPath.extract("$.data['a.b'][*].id", from: data)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(results.utf8)) as? [Int], [1,2])
        XCTAssertEqual(try JSONPath.extract("$.data.null", from: data), "null")
        for path in ["data", "$..id", "$.missing", "$[?(@.id)]", "$[-1]"] { XCTAssertThrowsError(try JSONPath.extract(path, from: data), path) }
    }
    func testJSONDiffHandlesNullBooleanAndHeaderCase() throws {
        let a = APIResponse(status: 200, headers: [Field("Content-Type", "application/json")], body: Data(#"{"same":1,"changed":true,"removed":null}"#.utf8), duration: 0, url: "")
        let b = APIResponse(status: 201, headers: [Field("content-type", "application/json"), Field("X-Test", "yes")], body: Data(#"{"same":1,"changed":1,"added":null}"#.utf8), duration: 0, url: "")
        let changes = try ResponseDiff.compare(a,b)
        XCTAssertEqual(changes.count, 5)
        XCTAssertTrue(changes.contains { $0.path == "$[\"changed\"]" && $0.before == "true" && $0.after == "1" })
        XCTAssertTrue(changes.contains { $0.path == "$[\"removed\"]" && $0.before == "null" && $0.after == nil })
    }
}

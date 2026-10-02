import XCTest
import MonkeytailCore
@testable import Monkeytail

@MainActor final class WatchTransferTests: XCTestCase {
    func testPrivateFieldsOmittedAndExplicitlyIncluded() throws {
        var request = APIRequest(url: "https://example.com/run?token=hidden&keep=yes")
        request.favorite = true; request.bodyKind = .json; request.body = "{\"password\":\"private\"}"
        request.auth.kind = .bearer; request.auth.token = "bearer-secret"
        var marked = Field("X-Custom", "private"); marked.secret = true
        request.headers += [marked, Field("X-Indirect", "{{private_value}}")]
        let safe = try WatchCompanionLink.prepare(request, variables: ["private_value": "indirect-secret"], proxy: ProxySettings(), includePrivateData: false, secretVariableNames: ["private_value"])
        XCTAssertNil(safe.body); XCTAssertNil(try safe.request().value(forHTTPHeaderField: "Authorization")); XCTAssertNil(try safe.request().value(forHTTPHeaderField: "X-Custom")); XCTAssertNil(try safe.request().value(forHTTPHeaderField: "X-Indirect")); XCTAssertFalse(safe.url.contains("hidden")); XCTAssertTrue(safe.url.contains("keep=yes"))
        let full = try WatchCompanionLink.prepare(request, variables: ["private_value": "indirect-secret"], proxy: ProxySettings(), includePrivateData: true)
        XCTAssertEqual(full.body, Data(request.body.utf8)); XCTAssertEqual(try full.request().value(forHTTPHeaderField: "Authorization"), "Bearer bearer-secret")
    }
    func testUnsupportedTransportAndPrivateURLRejected() throws {
        var request = APIRequest(url: "https://example.com/{{private_value}}")
        XCTAssertThrowsError(try WatchCompanionLink.prepare(request, variables: ["private_value": "private-path"], proxy: ProxySettings(), includePrivateData: false, secretVariableNames: ["private_value"]))
        request.transport = .websocket
        XCTAssertThrowsError(try WatchCompanionLink.prepare(request, variables: [:], proxy: ProxySettings(), includePrivateData: true))
    }
}

import XCTest
import MonkeytailCompanion
final class WatchHTTPTests: XCTestCase {
    func testResponseFormattingPreservesBytesAndBoundsPreview() async throws {
        var request = WatchRequest.sample; request.url = "http://127.0.0.1:8766/echo"
        let response = try await WatchHTTPClient(request).send()
        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(response.pretty.contains("headers"))
        XCTAssertTrue(response.hex.hasPrefix("00000000"))
    }
    func testRedirectDropsMarkedAndStandardCredentials() async throws {
        var request = WatchRequest.sample; request.url = "http://127.0.0.1:8766/cross-origin"
        request.headers = ["X-Custom": "secret", "Authorization": "Bearer private", "X-API-Key": "secret", "X-Public": "keep"]
        request.sensitiveHeaders = ["X-Custom"]
        let response = try await WatchHTTPClient(request).send()
        let value = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
        let headers = (value["headers"] as! [String: String]).reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
        XCTAssertNil(headers["authorization"]); XCTAssertNil(headers["x-custom"]); XCTAssertNil(headers["x-api-key"]); XCTAssertEqual(headers["x-public"], "keep")
        request.followRedirects = false
        let stopped = try await WatchHTTPClient(request).send(); XCTAssertEqual(stopped.status, 302)
    }
    func testOversizeAndCancellation() async throws {
        var request = WatchRequest.sample; request.url = "http://127.0.0.1:8766/oversize"
        do { _ = try await WatchHTTPClient(request).send(); XCTFail("Oversized response accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("256 KB")) }
        request.url = "http://127.0.0.1:8766/slow"
        let task = Task { try await WatchHTTPClient(request).send() }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch {}
    }
}

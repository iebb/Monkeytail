import XCTest
import MonkeytailCompanion

final class WatchTests: XCTestCase {
    func testPayloadRoundTripAndLimits() throws {
        var original = WatchRequest.sample
        original.method = "POST"; original.body = Data([0, 128, 255]); original.sensitiveHeaders = ["X-Custom"]
        XCTAssertEqual(try WatchPayload.decode(WatchPayload.encode([original])), [original])
        XCTAssertThrowsError(try WatchPayload.encode([original, original]))
        XCTAssertThrowsError(try WatchPayload.encode((0..<11).map { _ in WatchRequest.sample }))
        XCTAssertThrowsError(try WatchPayload.decode(Data(repeating: 0, count: WatchPayload.maximumBytes + 1)))
        original.body = Data(repeating: 0, count: 32769)
        XCTAssertThrowsError(try original.request())
    }
    func testRejectsUnsafeHeadersURLsAndTimeouts() throws {
        for url in ["file:///etc/hosts", "https://name:password@example.com", "javascript:alert(1)"] {
            var request = WatchRequest.sample; request.url = url; XCTAssertThrowsError(try request.request())
        }
        var request = WatchRequest.sample; request.headers = ["X-Test": "ok\r\nInjected: true"]
        XCTAssertThrowsError(try request.request())
        request.headers = ["Bad Header": "value"]; XCTAssertThrowsError(try request.request())
        request.headers = [:]; request.timeout = .infinity; XCTAssertThrowsError(try request.request())
        request.timeout = 31; XCTAssertThrowsError(try request.request())
    }
}

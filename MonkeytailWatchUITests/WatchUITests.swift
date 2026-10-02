import XCTest
final class WatchUITests: XCTestCase {
    func testFavouriteRequestSendAndVisibleResponse() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/echo"; app.launch()
        let request = app.buttons["Watch request Sample JSON"]; XCTAssertTrue(request.waitForExistence(timeout: 15)); request.tap()
        let send = app.buttons["Watch send request"]; XCTAssertTrue(send.waitForExistence(timeout: 5)); send.tap()
        let status = app.staticTexts["Watch response status"]; XCTAssertTrue(status.waitForExistence(timeout: 15)); XCTAssertTrue(status.label.hasPrefix("200"))
        let bodyLink = app.buttons["Watch view body"]
        if !bodyLink.isHittable { app.swipeUp() }
        bodyLink.tap()
        let body = app.descendants(matching: .any).matching(identifier: "Watch response body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5)); XCTAssertTrue(body.label.contains("headers"))
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Watch body accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}

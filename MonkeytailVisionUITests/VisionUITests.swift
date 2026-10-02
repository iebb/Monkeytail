import XCTest
final class VisionUITests: XCTestCase {
    func testNativeRequestAndVisibleJSONBody() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/captured-body-layout"; app.launch()
        let send = app.buttons["Send request"]; XCTAssertTrue(send.waitForExistence(timeout: 15)); send.tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        let body = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "#0000000")).firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 10)); XCTAssertTrue(body.isHittable)
        XCTAssertTrue(send.isHittable)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Native visionOS JSON response"; shot.lifetime = .keepAlways; add(shot)
    }
}

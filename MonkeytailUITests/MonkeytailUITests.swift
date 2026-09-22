import XCTest

final class MonkeytailUITests: XCTestCase {
    func testSendInspectImportAndAdaptiveLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/echo"
        app.launch()
        let send = app.buttons["Send request"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        send.tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        attach(app, name: "Pretty response")
        let search = app.textFields["Find in response"]
        search.tap()
        search.typeText("Hello from Monkeytail")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hello from Monkeytail")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Clear search"].tap()
        app.buttons["Tree"].tap()
        XCTAssertTrue(app.staticTexts["data"].waitForExistence(timeout: 3))
        attach(app, name: "Response tree")
        app.buttons["Workspace actions"].tap()
        app.buttons["Import workspace"].tap()
        let editor = app.textViews["Import content"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("curl 'http://127.0.0.1:8766/echo' -H 'X-Imported: yes'")
        app.buttons["Confirm import"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.textFields["Request URL"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Request URL"].value as? String, "http://127.0.0.1:8766/echo")
        XCTAssertEqual(app.textFields["Request name"].value as? String, "127.0.0.1")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "X-Imported")).firstMatch.exists)
        let headerValue = app.textFields["Header value"].firstMatch
        headerValue.tap()
        headerValue.typeText("-edited")
        if app.buttons["Response"].exists {
            app.buttons["Response"].tap()
            XCTAssertTrue(app.staticTexts["No response"].waitForExistence(timeout: 3))
            let keyboardDismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 3), .completed)
            app.buttons["Request"].tap()
        }
        XCTAssertEqual(headerValue.value as? String, "yes-edited")
        XCTAssertTrue(send.isHittable)
        attach(app, name: "Imported request")
        app.buttons["Workspace actions"].tap()
        app.buttons["Export cURL"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "X-Imported: yes-edited")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Copy"].tap()
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Send request"].waitForExistence(timeout: 5))
        attach(app, name: "Landscape workspace")
        XCUIDevice.shared.orientation = .portrait
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

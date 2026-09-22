import XCTest

final class MonkeytailUITests: XCTestCase {
    func testResponseBodyAfterKeyboardAndRepeatedRequests() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/echo"
        app.launch()
        app.buttons["HTTP method"].tap()
        app.buttons["POST"].tap()
        app.textFields["Request URL"].tap()
        app.buttons["Send request"].tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        let bodyLine = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hello from Monkeytail")).firstMatch
        app.buttons["Raw"].tap()
        XCTAssertTrue(bodyLine.waitForExistence(timeout: 5))
        XCTAssertTrue(bodyLine.isHittable)
        app.buttons["Copy response"].tap()
        let search = app.textFields["Find in response"]
        search.tap()
        search.typeText("Hello")
        XCTAssertTrue(bodyLine.isHittable)
        app.buttons["Clear search"].tap()
        for _ in 0..<3 {
            if app.buttons["Request"].exists { app.buttons["Request"].tap() }
            app.textFields["Request URL"].tap()
            app.buttons["Send request"].tap()
            XCTAssertTrue(bodyLine.waitForExistence(timeout: 5))
            XCTAssertTrue(bodyLine.isHittable)
            XCTAssertGreaterThanOrEqual(bodyLine.frame.minY, search.frame.maxY)
            XCTAssertLessThan(bodyLine.frame.maxY, app.buttons["Send request"].frame.minY)
        }
        app.buttons["Tree"].tap()
        XCTAssertTrue(app.staticTexts["data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["data"].isHittable)
        app.buttons["Raw"].tap()
        XCTAssertTrue(bodyLine.waitForExistence(timeout: 5))
        XCTAssertTrue(bodyLine.isHittable)
        attach(app, name: "Raw after keyboard and repeated requests")
    }

    func testResponseBodyRemainsVisibleWhenChangingFormats() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/body-layout"
        app.launch()
        app.buttons["Send request"].tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        let bodyLine = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hello from Monkeytail")).firstMatch
        XCTAssertTrue(bodyLine.waitForExistence(timeout: 5))
        attach(app, name: "Initial pretty response")
        let bodyScroll = app.scrollViews["Response body"]
        XCTAssertTrue(bodyScroll.isHittable)
        for _ in 0..<3 { bodyScroll.swipeUp() }
        XCTAssertFalse(bodyLine.isHittable, "The long response must actually scroll before changing formats")
        attach(app, name: "Scrolled pretty response")
        app.buttons["Raw"].tap()
        attach(app, name: "Raw response visibility")
        XCTAssertTrue(bodyLine.waitForExistence(timeout: 5))
        XCTAssertTrue(bodyLine.isHittable, "Raw response must be visible without scrolling")
        XCTAssertGreaterThan(bodyLine.frame.height, 0)
        XCTAssertTrue(app.frame.intersects(bodyLine.frame))
        XCTAssertGreaterThanOrEqual(bodyLine.frame.minY, app.textFields["Find in response"].frame.maxY)
        app.buttons["Copy response"].tap()
        if app.buttons["Request"].exists {
            app.buttons["Request"].tap()
            app.buttons["Response"].tap()
            XCTAssertTrue(bodyLine.isHittable)
        }
        for _ in 0..<3 { bodyScroll.swipeLeft() }
        app.buttons["Pretty"].tap()
        attach(app, name: "Pretty after horizontal scroll")
        XCTAssertTrue(bodyLine.waitForExistence(timeout: 5))
        XCTAssertTrue(bodyLine.isHittable)
        XCTAssertGreaterThanOrEqual(bodyLine.frame.minX, app.frame.minX)
        XCTAssertGreaterThanOrEqual(bodyLine.frame.minY, app.textFields["Find in response"].frame.maxY)
        app.buttons["Raw"].tap()
        for _ in 0..<3 { bodyScroll.swipeLeft() }
        XCTAssertLessThan(bodyLine.frame.minX, app.frame.minX, "Raw must actually scroll before sending again")
        app.buttons["Send request"].tap()
        let resetToLeading = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            bodyLine.exists && bodyLine.frame.minX >= app.frame.minX && bodyLine.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resetToLeading], timeout: 5), .completed)
        attach(app, name: "Raw response after sending again")
    }

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

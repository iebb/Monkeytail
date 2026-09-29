import XCTest

final class MonkeytailUITests: XCTestCase {
    private func selectFormat(_ name: String, in app: XCUIApplication) {
        app.buttons["Response format"].tap()
        app.buttons["Response format " + name].tap()
    }

    func testMIMEBodyPreviewsAndBytes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        for (path, expected) in [("binary", "Hex"), ("png", "Image"), ("wav", "Audio"), ("mp4", "Video"), ("fake-image", "Hex"), ("fake-audio", "Audio")] {
            app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/media/" + path
            app.launch()
            app.buttons["Send request"].tap()
            XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15), path)
            XCTAssertTrue(app.buttons["Response format"].label.contains(expected), path)
            if path == "png" {
                XCTAssertTrue(app.images["Response image preview"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.images["Response image preview"].isHittable)
            } else if path == "wav" || path == "mp4" {
                let player = app.descendants(matching: .any).matching(identifier: "Response media player").firstMatch
                XCTAssertTrue(player.waitForExistence(timeout: 10), path)
                XCTAssertTrue(player.isHittable, path)
                if path == "wav" {
                    app.buttons["Play audio"].tap()
                    XCTAssertTrue(app.buttons["Pause audio"].waitForExistence(timeout: 1))
                    app.buttons["Pause audio"].tap()
                }
            } else if path == "fake-audio" {
                XCTAssertTrue(app.staticTexts["Media preview error"].waitForExistence(timeout: 10))
            }
            XCTAssertTrue(app.buttons["Send request"].isHittable, path)
            XCTAssertLessThan(app.buttons["Send request"].frame.maxY, app.frame.maxY, path)
            attach(app, name: "MIME " + path)
            selectFormat("Hex", in: app)
            let row = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "00000000")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), path)
            XCTAssertTrue(row.isHittable, path)
            selectFormat("Binary", in: app)
            XCTAssertTrue(row.waitForExistence(timeout: 5), path)
            XCTAssertTrue(row.isHittable, path)
            if path == "binary" { XCTAssertTrue(row.label.contains("00000000 00000001 00000010 00000011")) }
        }
    }

    func testImportedCapturedResponseAndShare() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Workspace actions"].tap()
        app.buttons["Import workspace"].tap()
        let editor = app.textViews["Import content"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("curl -X POST 'http://127.0.0.1:8766/captured-body-layout'")
        app.buttons["Confirm import"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["Send request"].tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["422 bytes"].exists)
        let code = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "#0000000")).firstMatch
        for format in ["Pretty", "Raw", "Tree"] {
            selectFormat(format, in: app)
            XCTAssertTrue(code.waitForExistence(timeout: 5), format)
            XCTAssertTrue(code.isHittable, format)
            XCTAssertGreaterThanOrEqual(code.frame.minY, app.textFields["Find in response"].frame.maxY, format)
            attach(app, name: "Captured response " + format)
        }
        app.buttons["Response actions"].tap()
        app.buttons["Export body"].tap()
        let copyAction = app.descendants(matching: .any).matching(identifier: "Copy").firstMatch
        XCTAssertTrue(copyAction.waitForExistence(timeout: 20), "The share sheet must contain actions. " + app.debugDescription)
        attach(app, name: "Captured response share sheet")
        copyAction.tap()
        XCTAssertTrue(app.buttons["Send request"].waitForExistence(timeout: 5))
        XCTAssertTrue(code.isHittable)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(code.isHittable)
    }

    func testCompactResponseSurvivesFormatAndLifecycleChanges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/compact-body-layout"
        app.launch()
        app.buttons["HTTP method"].tap()
        app.buttons["POST"].tap()
        app.buttons["Send request"].tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["422 bytes"].exists)
        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hello from Monkeytail")).firstMatch
        let search = app.textFields["Find in response"]
        func verifyVisible(_ name: String) {
            XCTAssertTrue(message.waitForExistence(timeout: 5), name)
            XCTAssertTrue(message.isHittable, name)
            XCTAssertGreaterThanOrEqual(message.frame.minX, app.frame.minX, name)
            XCTAssertGreaterThanOrEqual(message.frame.minY, search.frame.maxY, name)
            XCTAssertLessThan(message.frame.maxY, app.buttons["Send request"].frame.minY, name)
            attach(app, name: name)
        }
        verifyVisible("Compact Pretty")
        selectFormat("Raw", in: app)
        app.buttons["Copy response"].tap()
        verifyVisible("Compact Raw copied")
        XCUIDevice.shared.press(.home)
        app.activate()
        verifyVisible("Compact Raw after foreground")
        app.buttons["Headers"].tap()
        app.buttons["Body"].tap()
        verifyVisible("Compact Raw after Headers")
        app.buttons["Request"].tap()
        app.buttons["Response"].tap()
        verifyVisible("Compact Raw after Request")
        selectFormat("Tree", in: app)
        verifyVisible("Compact Tree")
        selectFormat("Pretty", in: app)
        verifyVisible("Compact Pretty after Tree")
        search.tap()
        search.typeText("Hello")
        verifyVisible("Compact filtered Pretty")
        app.buttons["Clear search"].tap()
        selectFormat("Raw", in: app)
        app.buttons["Send request"].tap()
        verifyVisible("Compact Raw after resend")
    }

    func testBrowserProfileImportEditSendAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/echo"
        app.launch()
        app.buttons["Workspace actions"].tap()
        app.buttons["Import workspace"].tap()
        let editor = app.textViews["Import content"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("curl-impersonate --impersonate chrome150:no 'http://127.0.0.1:8766/echo'")
        app.buttons["Confirm import"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["Auth"].tap()
        let profile = app.buttons["TLS profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["TLS profile"].isHittable)
        XCTAssertTrue(profile.label.contains("Chrome 150"))
        let headers = app.switches["Browser headers"]
        XCTAssertEqual(headers.value as? String, "0")
        headers.tap()
        profile.tap()
        app.buttons["Safari 26 · iOS"].tap()
        XCTAssertTrue(profile.label.contains("Safari 26 · iOS"))
        XCTAssertEqual(headers.value as? String, "1")
        attach(app, name: "Browser TLS profile")
        app.buttons["Send request"].tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        let browserAgent = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Safari/")).firstMatch
        XCTAssertTrue(browserAgent.waitForExistence(timeout: 5))
        app.buttons["Workspace actions"].tap()
        app.buttons["Export cURL"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "safari260_ios")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Copy"].tap()
        if app.buttons["Request"].exists { app.buttons["Request"].tap() }
        XCTAssertTrue(profile.label.contains("Safari 26 · iOS"))
        profile.tap()
        app.buttons["System"].tap()
        XCTAssertFalse(headers.exists)
        let sendIsReachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: app.buttons["Send request"])
        XCTAssertEqual(XCTWaiter.wait(for: [sendIsReachable], timeout: 5), .completed)
    }

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
        selectFormat("Raw", in: app)
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
        selectFormat("Tree", in: app)
        XCTAssertTrue(app.staticTexts["data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["data"].isHittable)
        selectFormat("Raw", in: app)
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
        selectFormat("Raw", in: app)
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
        selectFormat("Pretty", in: app)
        attach(app, name: "Pretty after horizontal scroll")
        XCTAssertTrue(bodyLine.waitForExistence(timeout: 5))
        XCTAssertTrue(bodyLine.isHittable)
        XCTAssertGreaterThanOrEqual(bodyLine.frame.minX, app.frame.minX)
        XCTAssertGreaterThanOrEqual(bodyLine.frame.minY, app.textFields["Find in response"].frame.maxY)
        selectFormat("Raw", in: app)
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
        selectFormat("Tree", in: app)
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

    func testDiagnosticsSnapshotAndJSONPathFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["MONKEYTAIL_TEST_URL"] = "http://127.0.0.1:8766/echo"
        app.launch(); app.buttons["Send request"].tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 15))
        app.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.staticTexts["DNS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["DNS"].isHittable)
        attach(app, name: "Request diagnostics")
        app.buttons["Body"].tap()
        app.buttons["Response actions"].tap(); app.buttons["Save snapshot"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        app.buttons["Response actions"].tap(); app.buttons["Extract JSONPath"].tap()
        let path = app.textFields["JSONPath expression"]
        XCTAssertTrue(path.waitForExistence(timeout: 5)); path.tap(); path.typeText(".data.platforms[*]")
        app.buttons["Extract"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "iPhone Duo")).firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "JSONPath extraction")
        app.buttons["Done"].tap()
        app.buttons["Response actions"].tap(); app.buttons["Compare snapshot"].tap()
        let baseline = app.buttons["Snapshot baseline"]
        XCTAssertTrue(baseline.waitForExistence(timeout: 5)); baseline.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Echo a request")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Identical status, headers, and body"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Workspace actions"].tap(); app.buttons["Snapshots"].tap()
        XCTAssertTrue(app.navigationBars["Snapshots"].waitForExistence(timeout: 5))
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Echo a request")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Response status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hello from Monkeytail")).firstMatch.isHittable)
        attach(app, name: "Saved response snapshot")
    }
    func testMultipartImportAndLocalOnlySyncSetting() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["Workspace actions"].tap(); app.buttons["Import workspace"].tap()
        let editor = app.textViews["Import content"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        editor.typeText("curl 'http://127.0.0.1:8766/upload' -F 'greeting=hello' -F 'upload=@sample.png;type=image/png'")
        app.buttons["Confirm import"].tap(); XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        app.buttons["Body"].tap()
        XCTAssertTrue(app.buttons["Choose file"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields.containing(NSPredicate(format: "value == %@", "upload")).firstMatch.exists)
        attach(app, name: "Multipart request editor")
        app.buttons["Workspace actions"].tap(); app.buttons["Connection settings"].tap()
        let sync = app.switches["iCloud sync"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5)); XCTAssertEqual(sync.value as? String, "0")
        attach(app, name: "Optional iCloud sync")
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

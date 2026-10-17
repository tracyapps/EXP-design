import XCTest
import AppKit
import ApplicationServices

/// Runtime checks of a disposable, re-identified build. Never launches the
/// owner's installed bundle or accepts an arbitrary document path.
@MainActor
final class EditorAccessibilityTests: XCTestCase {
    private var app: XCUIApplication!
    private var fixture: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["EXP_A11Y_APP_PATH"],
              let directory = environment["EXP_A11Y_FIXTURE_DIR"],
              path.contains("/output/a11y/"), directory.contains("/output/a11y/"),
              let bundle = Bundle(path: path),
              let identity = environment["EXP_A11Y_BUNDLE_ID"],
              identity.hasPrefix("design.tapps.exp.a11y-fixture."),
              bundle.bundleIdentifier == identity else {
            throw XCTSkip("Run npm run test:a11y -- --interactive; isolated app/fixtures are required.")
        }
        fixture = URL(fileURLWithPath: directory).appendingPathComponent("Keyboard Fixture.design")
        let model: [String: Any] = ["artboards": [["id": UUID().uuidString, "name": "Keyboard Artboard",
            "frame": [[0, 0], [393, 852]]]], "nodes": []]
        try JSONSerialization.data(withJSONObject: model).write(to: fixture)
        app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
                               "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"]
        app.launch()
        app.typeKey(.escape, modifierFlags: []) // Dismiss a first-launch file chooser.
        app.open(fixture)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
    }

    override func tearDownWithError() throws {
        if let app {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "Native accessibility tree"
            tree.lifetime = .keepAlways
            add(tree)
            if app.windows.firstMatch.exists {
                let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                screenshot.name = "Native editor"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            app.terminate()
        }
    }

    func testNamedEditorControlsAndCanvas() {
        for name in ["Select", "Rectangle", "Ellipse", "Zoom in", "Zoom out", "Hide left panel", "Hide right panel"] {
            XCTAssertTrue(app.buttons[name].firstMatch.waitForExistence(timeout: 5), "Missing named control: \(name)")
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Design canvas")).firstMatch.exists)
        XCTAssertTrue(app.textFields["Zoom percentage"].firstMatch.exists)
    }

    private func focusedElement() throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw XCTSkip("Native focus assertions need Accessibility permission for the test runner.") }
        let identity = try XCTUnwrap(ProcessInfo.processInfo.environment["EXP_A11Y_BUNDLE_ID"])
        let running = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: identity).first)
        let application = AXUIElementCreateApplication(running.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
        XCTAssertEqual(result, .success)
        let element = try XCTUnwrap(value)
        XCTAssertEqual(CFGetTypeID(element), AXUIElementGetTypeID())
        return element as! AXUIElement
    }

    func testKeyboardZoomAndTabTraversal() throws {
        let zoom = app.textFields["Zoom percentage"].firstMatch
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.click() // Establish a known start; the remainder uses key events.
        app.typeKey("a", modifierFlags: .command)
        app.typeText("100")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(String(describing: zoom.value ?? "").contains("100"))
        let initial = try focusedElement()
        app.typeKey(.tab, modifierFlags: [])
        let forward = try focusedElement()
        XCTAssertFalse(CFEqual(initial, forward), "Tab must move focus away from the zoom field")
        app.typeKey(.tab, modifierFlags: .shift)
        XCTAssertTrue(CFEqual(initial, try focusedElement()), "Shift-Tab must return to the zoom field")
    }

    func testOpenDialogEscapeAndKeyboardSave() {
        app.typeKey("o", modifierFlags: .command)
        let openPanel = app.sheets.firstMatch
        XCTAssertTrue(openPanel.waitForExistence(timeout: 5) || app.dialogs.firstMatch.exists || app.windows["Open"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.windows.firstMatch.exists)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertFalse(app.dialogs.firstMatch.exists)
        app.typeKey("s", modifierFlags: .command)
        // Existing fixture save should not ask to overwrite an owner's document.
        XCTAssertFalse(app.dialogs.firstMatch.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
    }

    func testVisibleEditorAccessibilityAudit() throws {
        // All findings remain failures, with xcresult details. Never blanket-ignore
        // contrast/description/action/parent-child findings to make the suite green.
        continueAfterFailure = true // Collect every visible finding in one pass.
        defer { continueAfterFailure = false }
        try app.performAccessibilityAudit { issue in
            let evidence = XCTAttachment(string: "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No element returned")")
            evidence.name = "Accessibility audit finding"
            evidence.lifetime = .keepAlways
            self.add(evidence)
            return false // Attach evidence, and keep the issue as a test failure.
        }
    }
}

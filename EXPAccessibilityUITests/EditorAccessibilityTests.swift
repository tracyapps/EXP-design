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
        var model: [String: Any] = ["artboards": [["id": UUID().uuidString, "name": "Keyboard Artboard",
            "frame": [[0, 0], [393, 852]]]], "nodes": []]
        if name.contains("testAutoPaddingStaysInsidePanel") {
            func shape(_ x: Int) -> [String: Any] {
                ["id": UUID().uuidString, "name": "Vector", "frame": [[x, 20], [80, 60]],
                 "content": ["rectangle": ["_0": [:]]]]
            }
            model["nodes"] = [["id": UUID().uuidString, "name": "Panel fixture",
                               "frame": [[30, 30], [180, 80]],
                               "content": ["group": ["children": [shape(0), shape(90)]]]]]
        }
        if name.contains("testPattern") || name.contains("testComponentBounds") {
            model["nodes"] = [["id": UUID().uuidString, "name": "Pattern host", "frame": [[30, 30], [80, 60]],
                               "content": ["rectangle": ["_0": [:]]]]]
        }
        try JSONSerialization.data(withJSONObject: model).write(to: fixture)
        app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
                               "-SUEnableAutomaticChecks", "NO", "-SUAutomaticallyUpdate", "NO"]
        if name.contains("testLargerControlsAndVisibleGuidance") {
            app.launchArguments += ["-exp.pref.interfaceTypeSize", "extraLarge",
                                    "-exp.pref.largerInterfaceTargets", "YES",
                                    "-exp.pref.interfaceGuidance", "always",
                                    "-exp.pref.toolbarLabels", "iconsAndText"]
        }
        if name.contains("testIconsOnlyToolbarPreservesGuidanceAndAccessibleNames") {
            app.launchArguments += ["-exp.pref.interfaceGuidance", "always",
                                    "-exp.pref.largerInterfaceTargets", "YES",
                                    "-exp.pref.toolbarLabels", "iconsOnly"]
        }
        if name.contains("testAutoPaddingStaysInsidePanel") {
            app.launchArguments += ["-exp.pref.interfaceTypeSize", name.contains("ExtraLarge") ? "extraLarge" : "compact",
                                    "-exp.pref.largerInterfaceTargets", name.contains("LargerTargets") ? "YES" : "NO",
                                    "-exp.pref.interfaceGuidance", "never",
                                    "-exp.pref.toolbarLabels", "iconsOnly"]
        }
        if name.contains("testSettingsCanOpenWithDetachedPanels") {
            app.launchArguments += ["-exp.sanaa.enabled", "YES"]
        }
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

    func testSettingsAccessibilityChoicesApplyLive() {
        app.typeKey(",", modifierFlags: .command)
        let navigation = app.staticTexts["Accessibility"].firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        navigation.click()
        let larger = app.checkBoxes["Larger click targets"].firstMatch
        XCTAssertTrue(larger.waitForExistence(timeout: 5))
        larger.click()
        let rectangle = app.buttons["Rectangle"].firstMatch
        let changed = NSPredicate { _, _ in rectangle.exists && rectangle.frame.height >= 44 }
        expectation(for: changed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        // Restore the fixture's preference so other tests retain their baseline.
        larger.click()
        let panelHelp = app.popUpButtons["Panel help text"].firstMatch
        XCTAssertTrue(panelHelp.exists)
        let explanation = app.staticTexts["Size is the distance between grid lines in points. Subdiv is the number of smaller divisions in each cell."].firstMatch
        panelHelp.click()
        app.menuItems["Show"].firstMatch.click()
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        panelHelp.click()
        app.menuItems["Hide"].firstMatch.click()
        expectation(for: NSPredicate { _, _ in !explanation.exists }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        panelHelp.click()
        app.menuItems["Automatic with VoiceOver"].firstMatch.click()
        XCTAssertTrue(app.popUpButtons["Interface type size"].firstMatch.exists)
        XCTAssertFalse(app.popUpButtons["Drawing toolbar labels"].exists)
        app.staticTexts["General"].firstMatch.click()
        XCTAssertFalse(app.popUpButtons["Interface type size"].exists)
        let labels = app.popUpButtons["Drawing toolbar labels"].firstMatch
        XCTAssertTrue(labels.exists)
        labels.click()
        app.menuItems["Icons and text"].firstMatch.click()
        let expanded = NSPredicate { _, _ in rectangle.exists && rectangle.frame.width > 100 }
        expectation(for: expanded, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        labels.click()
        app.menuItems["Icons only"].firstMatch.click()
        let compact = NSPredicate { _, _ in rectangle.exists && rectangle.frame.width < 100 }
        expectation(for: compact, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        labels.click()
        app.menuItems["Automatic with VoiceOver"].firstMatch.click()
    }

    func testIconsOnlyToolbarPreservesGuidanceAndAccessibleNames() {
        let rectangle = app.buttons["Rectangle"].firstMatch
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        XCTAssertLessThan(rectangle.frame.width, 100, "Icons-only must override always-visible guidance")
        XCTAssertGreaterThanOrEqual(rectangle.frame.height, 44, "Larger targets remain independent")
        XCTAssertFalse(app.staticTexts["Rectangle"].exists)
        XCTAssertTrue(app.staticTexts["Size is the distance between grid lines in points. Subdiv is the number of smaller divisions in each cell."].exists)
    }

    func testUniversalNamesAndDecorativeImages() {
        for name in ["Grid size", "Grid subdivisions"] {
            XCTAssertTrue(app.textFields[name].firstMatch.waitForExistence(timeout: 5), "Missing field name: \(name)")
        }
        XCTAssertFalse(app.images["rectangle.3.group"].exists, "Decorative empty-state image must not become a spoken symbol name")
    }

    func testLargerControlsAndVisibleGuidance() {
        let rectangle = app.buttons["Rectangle"].firstMatch
        XCTAssertTrue(rectangle.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(rectangle.frame.height, 44)
        XCTAssertGreaterThan(rectangle.frame.width, 100, "Tool name should be visible beside its icon")
        let grid = app.textFields["Grid size"].firstMatch
        // AppKit exposes the inner text editor's bounds, not the surrounding
        // styled hit target. Exercise the added padding with a real pointer.
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -4)).click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("75")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(String(describing: grid.value ?? ""), "75", "Clicking the enlarged field padding must focus its editor")
        XCTAssertTrue(app.staticTexts["Size is the distance between grid lines in points. Subdiv is the number of smaller divisions in each cell."].exists)
    }

    func testAutoPaddingStaysInsidePanelLargerTargets() { checkAutoPaddingPanel() }
    func testAutoPaddingStaysInsidePanelExtraLarge() { checkAutoPaddingPanel() }
    func testAutoPaddingStaysInsidePanel() { checkAutoPaddingPanel() }

    private func checkAutoPaddingPanel() {
        let canvas = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Design canvas")).firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        for name in ["Collapse Handoff", "Collapse Design Language", "Collapse Components"] {
            let button = app.buttons[name].firstMatch
            if button.exists { button.click() }
        }
        app.staticTexts["Panel fixture"].firstMatch.click()
        let layout = app.checkBoxes["Auto Layout"].firstMatch
        XCTAssertTrue(layout.waitForExistence(timeout: 5))
        layout.click()
        XCTAssertTrue(app.textFields["Gap between items"].firstMatch.waitForExistence(timeout: 5))
        let padding = app.checkBoxes["Auto Padding"].firstMatch
        XCTAssertTrue(padding.waitForExistence(timeout: 5))
        padding.click()
        let stroke = app.textFields["Background stroke width"].firstMatch
        XCTAssertTrue(stroke.waitForExistence(timeout: 5))
        let right = app.windows.firstMatch.frame.maxX - 8
        for name in ["Top padding", "Right padding", "Bottom padding", "Left padding", "Top margin", "Right margin", "Bottom margin", "Left margin", "Background stroke width", "Gap between items", "Rotation", "Layer opacity"] {
            let field = app.textFields[name].firstMatch
            XCTAssertTrue(field.exists, "Missing field: \(name)")
            XCTAssertGreaterThanOrEqual(field.frame.minX, app.buttons["Properties"].firstMatch.frame.minX - 6)
            XCTAssertLessThanOrEqual(field.frame.maxX, right, "\(name) must remain inside the panel")
        }
        let top = app.textFields["Top padding"].firstMatch
        top.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("24")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(String(describing: top.value ?? ""), "24")
        let unite = app.buttons["Unite"].firstMatch
        XCTAssertTrue(unite.exists)
        for name in ["Unite", "Subtract", "Intersect", "Exclude"] {
            let button = app.buttons[name].firstMatch
            XCTAssertTrue(button.exists)
            XCTAssertLessThanOrEqual(button.frame.height, self.name.contains("LargerTargets") ? 44 : (self.name.contains("ExtraLarge") ? 42 : 28))
            XCTAssertLessThanOrEqual(button.frame.maxX, right)
            XCTAssertEqual(button.frame.minY, unite.frame.minY, accuracy: 1)
        }
        XCTAssertLessThanOrEqual(app.buttons["Align bottom edges"].firstMatch.frame.maxX, right)
        XCTAssertFalse(app.staticTexts["Unite needs visible, unlocked closed vectors in folders without backgrounds, effects or masks."].exists)
    }

    private func collapseOtherRightPanels() {
        for name in ["Collapse Handoff", "Collapse Design Language", "Collapse Components"] {
            let button = app.buttons[name].firstMatch
            if button.exists { button.click() }
        }
    }

    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click(); app.typeKey("a", modifierFlags: .command)
        app.typeText(value); app.typeKey(.return, modifierFlags: [])
    }

    func testPatternCreationFromEmptyFillAndReopen() {
        collapseOtherRightPanels()
        app.staticTexts["Pattern host"].firstMatch.click()
        app.buttons["Edit fill"].firstMatch.click()
        let mode = app.radioButtons["Pattern"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.click()
        let create = app.buttons["New Pattern…"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.click()
        let editor = app.windows["Edit Pattern"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        replace(editor.textFields["Pattern tile width"].firstMatch, with: "160")
        XCTAssertEqual(String(describing: editor.textFields["Pattern tile width"].firstMatch.value ?? ""), "160")
        app.typeKey("w", modifierFlags: .command)
        app.buttons["Edit fill"].firstMatch.click()
        let edit = app.buttons["Edit this pattern's tile"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.click()
        XCTAssertTrue(app.windows["Edit Pattern"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(String(describing: app.textFields["Pattern tile width"].firstMatch.value ?? ""), "160")
        app.typeKey("s", modifierFlags: .command)
    }

    func testPatternLibraryCreatesFirstTile() {
        let tab = app.buttons["Patterns"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.click()
        let create = app.buttons["New Pattern…"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.click()
        XCTAssertTrue(app.windows["Edit Pattern"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["Pattern tile width"].firstMatch.exists)
    }

    func testComponentBoundsResizeAndFit() {
        app.staticTexts["Pattern host"].firstMatch.click()
        app.menuBars.menuBarItems["Object"].click()
        app.menuItems["Create Component"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Instance"].firstMatch.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["Object"].click()
        app.menuItems["Edit Component"].firstMatch.click()
        let editor = app.windows["Edit Component"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        replace(editor.textFields["Component bounds width"].firstMatch, with: "140")
        XCTAssertEqual(String(describing: editor.textFields["Component bounds width"].firstMatch.value ?? ""), "140")
        editor.buttons["Fit to Artwork"].firstMatch.click()
        XCTAssertEqual(String(describing: editor.textFields["Component bounds width"].firstMatch.value ?? ""), "80")
        app.typeKey("s", modifierFlags: .command)
    }

    func testSettingsCanOpenWithDetachedPanels() {
        app.menuButtons["Workspace mode"].firstMatch.click()
        app.menuItems["Multi-Window"].firstMatch.click()
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Sanaa"].firstMatch.click()
        let settingsButton = app.buttons["Agent settings"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8)); settingsButton.click()
        let general = app.staticTexts["General"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 8))
        general.click()
        XCTAssertTrue(app.popUpButtons["Drawing toolbar labels"].firstMatch.isHittable)
        let identity = ProcessInfo.processInfo.environment["EXP_A11Y_BUNDLE_ID"]!
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: identity).first!.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let peers = windows.filter { info in
            guard (info[kCGWindowOwnerPID as String] as? Int) == Int(pid),
                  let box = info[kCGWindowBounds as String] as? [String: Any],
                  let width = box["Width"] as? Double, let height = box["Height"] as? Double else { return false }
            return width > 200 && height > 150
        }
        XCTAssertGreaterThanOrEqual(peers.count, 3, "Settings, canvas and detached panels must be visible")
        for info in peers { XCTAssertEqual(info[kCGWindowLayer as String] as? Int, 0, "Peer windows must use normal ordering") }
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Properties"].firstMatch.click()
        let properties = app.dialogs["Properties"].firstMatch
        XCTAssertTrue(properties.waitForExistence(timeout: 5), "Menu must reveal the existing panel, not hide it")
        XCTAssertTrue(properties.staticTexts["Properties"].firstMatch.isHittable)
        XCTAssertTrue(properties.textFields["Grid size"].firstMatch.isHittable, "Raised panel must accept interaction above Settings")
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

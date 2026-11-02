import XCTest

/// Taps the "Try it" field so the Gramkey keyboard comes up, then saves screenshots.
/// Run with TEST_RUNNER_SHOT_DIR=/some/dir to write PNGs (simulator shares the host filesystem).
private enum KeyboardHeight { static let total: CGFloat = 46 + 54 * 4 + 40 }   // mirrors KeyboardView.height(suggestions: true)

final class KeyboardScreenshotTests: XCTestCase {
    func testKeyboardScreenshot() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["Type here…"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        sleep(3)
        save("keyboard-letters")

    }

    /// Uses the in-app keyboard preview (`-previewKeyboard`) to capture the "+" editor bar.
    func testAddChipEditorScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["-previewKeyboard"]
        app.launch()
        let plus = app.buttons["addChip"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        // "+" sits at the end of a horizontally scrolling bar
        // Drag the bar by coordinates: chip labels like "Ctrl" also match rows in the app's own list.
        let h = app.windows.firstMatch.frame.height
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let barY = h - 34 - (KeyboardHeight.total + 30) + 23   // bottom safe area + preview padding + half bar
        for _ in 0..<4 {
            origin.withOffset(CGVector(dx: 380, dy: barY)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: 20, dy: barY)))
        }
        save("bar-end")
        plus.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        save("add-editor")
    }

    /// Long gestures for host-side `simctl io screenshot` (XCUITest can't screenshot mid-gesture):
    /// writes `<SHOT_DIR>/<name>.go` just before each gesture so a watcher knows when to capture.
    func testPopoutGestures() {
        let app = XCUIApplication()
        app.launchArguments = ["-previewKeyboard"]
        app.launch()
        let space = app.staticTexts["space"].firstMatch
        XCTAssertTrue(space.waitForExistence(timeout: 10))

        marker("callout")
        app.staticTexts["g"].firstMatch.press(forDuration: 3)   // key callout bubble

        marker("panel")
        let start = space.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // hold, then slide left onto "Copy" (cells are centred on the touch point) and keep holding
        start.press(forDuration: 0.7, thenDragTo: start.withOffset(CGVector(dx: -45, dy: -20)),
                    withVelocity: .slow, thenHoldForDuration: 3)
    }

    private func marker(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] else { return }
        FileManager.default.createFile(atPath: "\(dir)/\(name).go", contents: nil)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot); att.name = name; att.lifetime = .keepAlways; add(att)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

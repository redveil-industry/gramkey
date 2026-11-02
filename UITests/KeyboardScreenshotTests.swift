import XCTest

/// Taps the "Try it" field so the Gramkey keyboard comes up, then saves screenshots.
/// Run with TEST_RUNNER_SHOT_DIR=/some/dir to write PNGs (simulator shares the host filesystem).
private enum KeyboardHeight { static let total: CGFloat = 46 + 54 * 4 }   // mirrors KeyboardView.totalHeight

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

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot); att.name = name; att.lifetime = .keepAlways; add(att)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

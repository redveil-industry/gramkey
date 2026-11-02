import XCTest
@testable import Gramkey

final class GramkeyTests: XCTestCase {
    func testPayloadDecode() {
        XCTAssertEqual(Payload.decode("^C"), "\u{03}")
        XCTAssertEqual(Payload.decode("^c"), "\u{03}")
        XCTAssertEqual(Payload.decode("^["), "\u{1b}")
        XCTAssertEqual(Payload.decode("\\e[A"), "\u{1b}[A")
        XCTAssertEqual(Payload.decode("ls -la\\n"), "ls -la\n")
        XCTAssertEqual(Payload.decode("\\\\n"), "\\n")
        XCTAssertEqual(Payload.decode("a^"), "a^")       // trailing caret stays literal
        XCTAssertEqual(Payload.decode("^1"), "^1")       // not a control mapping
        XCTAssertEqual(Payload.decode("\\q"), "\\q")     // unknown escape stays literal
    }

    func testUpOffset() {
        XCTAssertEqual(TextNav.upOffset(before: "hello"), -5)          // first line → start
        XCTAssertEqual(TextNav.upOffset(before: "ab\ncd"), -3)         // same column above
        XCTAssertEqual(TextNav.upOffset(before: "abcd\nx"), -5)        // col 1 on longer line
        XCTAssertEqual(TextNav.upOffset(before: "a\nxyz"), -4)         // clamp to shorter line end
    }

    func testDownOffset() {
        XCTAssertEqual(TextNav.downOffset(before: "a", after: "b\ncd"), 3)
        XCTAssertEqual(TextNav.downOffset(before: "abc", after: "\nx"), 2)   // clamp to shorter line
        XCTAssertEqual(TextNav.downOffset(before: "x", after: "yz"), 2)      // last line → end
    }

    func testLineAndWordNav() {
        XCTAssertEqual(TextNav.lineStartOffset(before: "abc"), -3)
        XCTAssertEqual(TextNav.lineStartOffset(before: "abc\nde"), -2)
        XCTAssertEqual(TextNav.lineStartOffset(before: "abc\n"), 0)
        XCTAssertEqual(TextNav.lineStartOffset(before: ""), 0)
        XCTAssertEqual(TextNav.lineEndOffset(after: "xyz\nq"), 3)
        XCTAssertEqual(TextNav.lineEndOffset(after: ""), 0)
        XCTAssertEqual(TextNav.wordBackLength(before: "git status"), 6)
        XCTAssertEqual(TextNav.wordBackLength(before: "git status  "), 8)
        XCTAssertEqual(TextNav.wordBackLength(before: "one"), 3)
        XCTAssertEqual(TextNav.wordBackLength(before: ""), 0)
    }

    func testInferPayload() {
        XCTAssertEqual(Shortcut.inferPayload(from: "Ctrl+O"), "^O")
        XCTAssertEqual(Shortcut.inferPayload(from: "ctrl+t"), "^T")
        XCTAssertEqual(Shortcut.inferPayload(from: " clear "), "clear")      // plain label sends itself
        XCTAssertEqual(Shortcut.inferPayload(from: "Ctrl+1"), "Ctrl+1")      // not a control mapping
        XCTAssertEqual(Shortcut.inferPayload(from: "Ctrl+Alt"), "Ctrl+Alt")
        XCTAssertEqual(Payload.decode(Shortcut.inferPayload(from: "Ctrl+O")), "\u{0f}")
    }

    func testShortcutsRoundTrip() throws {
        let data = try JSONEncoder().encode(Shortcut.defaults)
        XCTAssertEqual(try JSONDecoder().decode([Shortcut].self, from: data), Shortcut.defaults)
    }
}

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

    func testSuggestions() {
        Suggestions.warmUp(); Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(Suggestions.currentWord(before: "hello wor"), "wor")
        XCTAssertEqual(Suggestions.currentWord(before: "don't"), "don't")
        XCTAssertEqual(Suggestions.currentWord(before: "end. "), "")
        XCTAssertEqual(Suggestions.candidates(for: "teh").first, "the")             // typo fix
        XCTAssertEqual(Suggestions.candidates(for: "recieve").first, "receive")
        XCTAssertEqual(Suggestions.candidates(for: "keyb").first, "keyboard")       // completion beats guess
        XCTAssertEqual(Suggestions.candidates(for: "th").first, "the")
        XCTAssertFalse(Suggestions.candidates(for: "keyboa").contains { $0.contains(" ") || $0.contains("-") })
        XCTAssertEqual(Suggestions.candidates(for: "Teh").first, "The")
        XCTAssertFalse(Suggestions.candidates(for: "hello").map { $0.lowercased() }.contains("hello"))
        XCTAssertEqual(Suggestions.candidates(for: ""), [])
    }

    func testTypoCost() {
        XCTAssertLessThan(Typo.cost(typed: "tge", intended: "the"), Typo.cost(typed: "tqe", intended: "the"))   // g~h adjacent
        XCTAssertEqual(Typo.cost(typed: "teh", intended: "the"), 0.5, accuracy: 0.001)                          // transposition
        XCTAssertEqual(Typo.cost(typed: "dont", intended: "don't"), 0.1, accuracy: 0.001)                       // apostrophe
        XCTAssertLessThan(Typo.cost(typed: "helo", intended: "hello"), Typo.cost(typed: "helo", intended: "help"))
        XCTAssertEqual(Typo.cost(typed: "same", intended: "same"), 0)
    }

    func testAutocorrect() {
        Suggestions.warmUp(); Thread.sleep(forTimeInterval: 0.5)
        let e = WordEngine()
        _ = e.correction(for: "teh"); Thread.sleep(forTimeInterval: 0.3)   // warm this instance's checker too
        XCTAssertEqual(e.correction(for: "teh"), "the")
        XCTAssertEqual(e.correction(for: "Teh"), "The")
        XCTAssertEqual(e.correction(for: "adn"), "and")
        XCTAssertEqual(e.correction(for: "dont"), "don't")
        XCTAssertEqual(e.correction(for: "recieve"), "receive")
        XCTAssertEqual(e.correction(for: "becuase"), "because")
        XCTAssertEqual(e.correction(for: "i"), "I")
        XCTAssertNil(e.correction(for: "hello"))        // real words untouched
        XCTAssertNil(e.correction(for: "the"))
        XCTAssertNil(e.correction(for: "qzxv"))         // nothing plausible: leave it

        // jargon you keep typing stops being "corrected"
        let jargon = "kubectl"
        e.learn(jargon, previous: nil); e.learn(jargon, previous: nil)
        XCTAssertNil(e.correction(for: jargon))
        // undoing a correction protects the original immediately
        e.reject("nmapp")
        XCTAssertNil(e.correction(for: "nmapp"))

        // text replacements expand; names are never corrected
        e.replacements["omw"] = "On my way!"
        XCTAssertEqual(e.correction(for: "omw"), "On my way!")
        e.names.insert("ismael")
        XCTAssertNil(e.correction(for: "Ismael"))
    }

    func testLearningAndPredictions() {
        let e = WordEngine()
        for _ in 0..<3 { e.learn("status", previous: "git") }
        e.learn("push", previous: "git")
        XCTAssertEqual(e.predictions(after: "git", sentenceStart: false).prefix(2), ["status", "push"])
        XCTAssertEqual(e.predictions(after: nil, sentenceStart: true), ["I", "The", "Thanks"])
        e.learn("sk-abc123", previous: nil)           // tokens/keys never stored
        e.learn("x", previous: nil)
        XCTAssertNil(e.memory.words["sk-abc123"])
        XCTAssertNil(e.memory.words["x"])
        XCTAssertEqual(e.suggestions(for: "sta", previous: nil).others.first, "status")   // your words first
    }

    func testContextHelpers() {
        XCTAssertEqual(Suggestions.previousWord(before: "git sta"), "git")
        XCTAssertEqual(Suggestions.previousWord(before: "git "), "git")
        XCTAssertNil(Suggestions.previousWord(before: "end. sta"))
        XCTAssertNil(Suggestions.previousWord(before: "sta"))
        XCTAssertTrue(Suggestions.isSentenceStart(""))
        XCTAssertTrue(Suggestions.isSentenceStart("Done. "))
        XCTAssertFalse(Suggestions.isSentenceStart("hello "))
    }

    func testHoldPanelIndex() {
        let w: CGFloat = 387
        typealias H = KeyboardState.Hold
        XCTAssertNil(KeyboardView.holdIndex(H(start: .init(x: 200, y: 180), current: .init(x: 204, y: 182)), width: w))
        let left = KeyboardView.panelLeft(H(start: .init(x: 200, y: 0), current: .zero), width: w)
        func at(_ x: CGFloat) -> Int? { KeyboardView.holdIndex(H(start: .init(x: 200, y: 180), current: .init(x: x, y: 150)), width: w) }
        XCTAssertEqual(at(left + 5 + 10), 0)
        XCTAssertEqual(at(left + 5 + KeyboardView.cellW * 3 + 10), 3)
        XCTAssertEqual(at(-50), 0)       // clamps
        XCTAssertEqual(at(900), 3)
        XCTAssertEqual(KeyboardView.panelLeft(H(start: .init(x: 5, y: 0), current: .zero), width: w), 0)
        XCTAssertEqual(KeyboardView.panelLeft(H(start: .init(x: 385, y: 0), current: .zero), width: w), w - KeyboardView.panelW)
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

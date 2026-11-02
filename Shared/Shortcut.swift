import Foundation

/// One chip in the shortcut bar. Shared between the container app (editor) and the keyboard.
struct Shortcut: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case text, copy, paste, left, right, up, down, backspace, forwardDelete, ctrl

        var id: String { rawValue }
        var title: String {
            switch self {
            case .text: "Send text / keys"
            case .copy: "Copy selection"
            case .paste: "Paste"
            case .left: "Arrow ←"
            case .right: "Arrow →"
            case .up: "Arrow ↑"
            case .down: "Arrow ↓"
            case .backspace: "Backspace"
            case .forwardDelete: "Forward delete"
            case .ctrl: "Ctrl (sticky modifier)"
            }
        }
        /// Holding the chip auto-repeats.
        var repeats: Bool { [.left, .right, .up, .down, .backspace, .forwardDelete].contains(self) }
    }

    var id = UUID()
    var label: String
    var kind: Kind
    /// Only for `.text`. Supports `\e \n \t \r \\` and caret notation `^C`.
    var payload = ""

    static let defaults: [Shortcut] = [
        .init(label: "Ctrl", kind: .ctrl),
        .init(label: "Copy", kind: .copy),
        .init(label: "Paste", kind: .paste),
        .init(label: "Esc", kind: .text, payload: "\\e"),
        .init(label: "Tab", kind: .text, payload: "\\t"),
        .init(label: "Shift+Tab", kind: .text, payload: "\\e[Z"),
        .init(label: "←", kind: .left),
        .init(label: "↑", kind: .up),
        .init(label: "↓", kind: .down),
        .init(label: "→", kind: .right),
        .init(label: "⌫", kind: .backspace),
        .init(label: "Del", kind: .forwardDelete),
    ] + ["C", "D", "Z", "L", "R", "A", "E", "W", "U"].map {
        .init(label: "Ctrl+\($0)", kind: .text, payload: "^\($0)")
    }
}

extension Shortcut {
    /// What a quick-added chip sends when the user leaves "Sends" empty: `Ctrl+O` → `^O`, otherwise the label itself.
    static func inferPayload(from label: String) -> String {
        let l = label.trimmingCharacters(in: .whitespaces)
        if l.lowercased().hasPrefix("ctrl+"), l.count == 6, let ch = l.last, Payload.control(for: ch) != nil {
            return "^\(ch.uppercased())"
        }
        return l
    }
}

enum Payload {
    /// Turns the editable notation into the characters actually inserted.
    static func decode(_ s: String) -> String {
        let c = Array(s)
        var out = ""
        var i = 0
        while i < c.count {
            if c[i] == "\\", i + 1 < c.count {
                switch c[i + 1] {
                case "e": out += "\u{1b}"
                case "n": out += "\n"
                case "t": out += "\t"
                case "r": out += "\r"
                case "\\": out += "\\"
                default: out.append(c[i]); out.append(c[i + 1])
                }
                i += 2
            } else if c[i] == "^", i + 1 < c.count, let ctl = control(for: c[i + 1]) {
                out += ctl
                i += 2
            } else {
                out.append(c[i])
                i += 1
            }
        }
        return out
    }

    /// Ctrl+<ch> as an ASCII control character (`A`→0x01, `[`→ESC), or nil if not mappable.
    static func control(for ch: Character) -> String? {
        guard let a = ch.uppercased().first?.asciiValue, (64...95).contains(a) else { return nil }
        return String(UnicodeScalar(a & 0x1f))
    }
}

/// Up/down cursor movement for plain text fields, where iOS only gives us a relative offset API.
/// shortcut: counts Characters and only sees the proxy's context window; fine for typical fields.
enum TextNav {
    static func upOffset(before: String) -> Int {
        let lines = before.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return -before.count }
        let col = lines[lines.count - 1].count
        let prev = lines[lines.count - 2].count
        return -(col + 1 + max(0, prev - col))
    }

    /// Ctrl+A / Ctrl+U: distance back to the start of the current line (≤ 0).
    static func lineStartOffset(before: String) -> Int {
        -(before.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0)
    }

    /// Ctrl+E / Ctrl+K: distance forward to the end of the current line (≥ 0).
    static func lineEndOffset(after: String) -> Int {
        after.split(separator: "\n", omittingEmptySubsequences: false).first?.count ?? 0
    }

    /// Ctrl+W: trailing whitespace plus the word before it.
    static func wordBackLength(before: String) -> Int {
        let spaces = before.reversed().prefix { $0.isWhitespace }.count
        return spaces + before.dropLast(spaces).reversed().prefix { !$0.isWhitespace }.count
    }

    static func downOffset(before: String, after: String) -> Int {
        let col = before.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0
        let lines = after.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return after.count }
        return lines[0].count + 1 + min(col, lines[1].count)
    }
}

/// App Group storage so the app's editor and the keyboard extension see the same config.
enum Store {
    static let defaults = UserDefaults(suiteName: "group.com.redveil.gramkey") ?? .standard

    static var shortcuts: [Shortcut] {
        get {
            guard let data = defaults.data(forKey: "shortcuts"),
                  let list = try? JSONDecoder().decode([Shortcut].self, from: data) else { return Shortcut.defaults }
            return list
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "shortcuts") }
    }

    /// Key-press haptics (default on). iOS only lets keyboards fire haptics with Full Access.
    static var haptics: Bool {
        get { !defaults.bool(forKey: "hapticsOff") }
        set { defaults.set(!newValue, forKey: "hapticsOff") }
    }

    static var autocorrect: Bool {
        get { !defaults.bool(forKey: "autocorrectOff") }
        set { defaults.set(!newValue, forKey: "autocorrectOff") }
    }

    /// Personal word memory for autocorrect/predictions. Typing-derived, so it's opt-out and clearable.
    static var learning: Bool {
        get { !defaults.bool(forKey: "learningOff") }
        set { defaults.set(!newValue, forKey: "learningOff") }
    }

    static var memory: WordEngine.Memory {
        get {
            guard let data = defaults.data(forKey: "wordMemory"),
                  let m = try? JSONDecoder().decode(WordEngine.Memory.self, from: data) else { return .init() }
            return m
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "wordMemory") }
    }

    /// On: arrows/Del emit ANSI escape sequences (terminals). Off: move the text cursor.
    static var arrowsSendANSI: Bool {
        get { defaults.bool(forKey: "arrowsSendANSI") }
        set { defaults.set(newValue, forKey: "arrowsSendANSI") }
    }
}

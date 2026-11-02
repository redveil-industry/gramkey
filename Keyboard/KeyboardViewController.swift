import OSLog
import SwiftUI
import UIKit

/// Shows in Xcode's console / Console.app. Logs action names and outcomes only, never typed text or payloads.
private let log = Logger(subsystem: "com.redveil.gramkey", category: "keyboard")

final class KeyboardViewController: UIInputViewController {
    private let state = KeyboardState()
    private var lastShiftTap = Date.distantPast
    private var lastSpace = Date.distantPast
    private var proxy: UITextDocumentProxy { textDocumentProxy }

    override func viewDidLoad() {
        super.viewDidLoad()
        state.send = { [weak self] in self?.handle($0) }

        let host = UIHostingController(rootView: KeyboardView(state: state))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardView.totalHeight)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        state.shortcuts = Store.shortcuts   // pick up edits made in the container app
        state.terminal = Store.arrowsSendANSI
        syncWithHost()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        syncWithHost()
    }

    private func syncWithHost() {
        state.isDark = proxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        state.needsGlobe = needsInputModeSwitchKey
        state.returnLabel = switch proxy.returnKeyType ?? .default {
        case .go: "go"
        case .search, .google, .yahoo: "search"
        case .send: "send"
        case .done: "done"
        case .next: "next"
        case .join: "join"
        default: nil
        }
        autoCapitalize()
    }

    // MARK: - Events

    private func handle(_ event: KeyEvent) {
        if state.draft != nil, editDraft(event) { return }
        if state.allSelected, consumeSelectAll(event) { return }
        switch event {
        case .char(let s):
            let text = state.shift == .off ? s : s.uppercased()
            if state.ctrl, let ctl = Payload.control(for: Character(text)) {
                state.ctrl = false
                send(ctl, label: "Ctrl+\(text.uppercased())")
            } else {
                proxy.insertText(text)
            }
            if state.shift == .once { state.shift = .off }
            if state.layer != .letters, s == "'" { state.layer = .letters }   // Apple's apostrophe behavior
            autoCapitalize()

        case .backspace:
            proxy.deleteBackward()
            autoCapitalize()

        case .space:
            // Apple: quick double-space after a word becomes ". "
            let before = proxy.documentContextBeforeInput ?? ""
            if Date().timeIntervalSince(lastSpace) < 0.4, before.hasSuffix(" "),
               let prev = before.dropLast().last, prev.isLetter || prev.isNumber {
                proxy.deleteBackward()
                proxy.insertText(". ")
                lastSpace = .distantPast
            } else {
                proxy.insertText(" ")
                lastSpace = Date()
            }
            if state.layer != .letters { state.layer = .letters }
            autoCapitalize()

        case .ret:
            proxy.insertText("\n")
            autoCapitalize()

        case .shift:
            let doubleTap = Date().timeIntervalSince(lastShiftTap) < 0.3
            lastShiftTap = Date()
            state.shift = doubleTap ? .locked : (state.shift == .off ? .once : .off)

        case .layer(let l):
            state.layer = l

        case .globe:
            advanceToNextInputMode()

        case .shortcut(let s):
            log.debug("chip \(s.label, privacy: .public) kind=\(s.kind.rawValue, privacy: .public) terminal=\(self.state.terminal)")
            run(s.kind, label: s.label, payload: s.payload)
            autoCapitalize()

        case .toggleTerminal:
            state.terminal.toggle()
            Store.arrowsSendANSI = state.terminal
            flash(state.terminal ? "Terminal mode: Ctrl/Esc/arrows send raw codes" : "Text mode: Ctrl keys edit text")
        }
    }

    /// Terminal mode inserts raw bytes (the PTY interprets them). Text mode maps control characters to
    /// editing commands, because inserting e.g. 0x01 into a normal field does nothing visible.
    private func send(_ out: String, label: String) {
        let isControl = { (u: Unicode.Scalar) in (u.value < 0x20 && u != "\n" && u != "\t") || u.value == 0x7f }
        if state.terminal || !out.unicodeScalars.contains(where: isControl) {
            proxy.insertText(out)
        } else if out.unicodeScalars.count == 1, let u = out.unicodeScalars.first {
            editingCommand(u.value, label: label)
        } else {
            log.debug("\(label, privacy: .public): escape sequence blocked in text mode")
            flash("\(label) needs Terminal mode (>_)")
        }
    }

    /// macOS/emacs text bindings, plus Ctrl+C/X/V as copy/cut/paste.
    private func editingCommand(_ code: UInt32, label: String) {
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        switch code {
        case 0x01: state.allSelected = true                                                                   // A: virtual select-all
        case 0x05: proxy.adjustTextPosition(byCharacterOffset: TextNav.lineEndOffset(after: after))          // E
        case 0x02: run(.left, label: label)                                                                   // B
        case 0x06: run(.right, label: label)                                                                  // F
        case 0x10: run(.up, label: label)                                                                     // P
        case 0x0E: run(.down, label: label)                                                                   // N
        case 0x04: run(.forwardDelete, label: label)                                                          // D
        case 0x08: proxy.deleteBackward()                                                                     // H
        case 0x03: run(.copy, label: label)                                                                   // C
        case 0x16: run(.paste, label: label)                                                                  // V
        case 0x18:                                                                                            // X
            let hadSelection = !(proxy.selectedText ?? "").isEmpty
            run(.copy, label: label)
            if hadSelection, hasFullAccess { proxy.deleteBackward() }
        case 0x0B:                                                                                            // K
            let n = TextNav.lineEndOffset(after: after)
            proxy.adjustTextPosition(byCharacterOffset: n)
            for _ in 0..<n { proxy.deleteBackward() }
        case 0x15: for _ in 0..<(-TextNav.lineStartOffset(before: before)) { proxy.deleteBackward() }         // U
        case 0x17: for _ in 0..<TextNav.wordBackLength(before: before) { proxy.deleteBackward() }             // W
        case 0x1B: dismissKeyboard()                                                                          // Esc
        default:
            log.debug("\(label, privacy: .public): no text-mode mapping")
            flash("\(label) only works in Terminal mode (>_)")
        }
    }

    private func run(_ kind: Shortcut.Kind, label: String, payload: String = "") {
        switch kind {
        case .text:
            send(Payload.decode(payload), label: label)
        case .copy:
            guard hasFullAccess else { return flash("Enable Full Access for Copy") }
            guard let sel = proxy.selectedText, !sel.isEmpty else {
                log.debug("copy: selectedText empty (host app may not expose it)")
                return flash("Nothing selected")
            }
            UIPasteboard.general.string = sel
            flash("Copied")
        case .paste:
            guard hasFullAccess else { return flash("Enable Full Access for Paste") }
            guard let text = UIPasteboard.general.string else { return flash("Clipboard empty") }
            proxy.insertText(text)
        case .left:
            state.terminal ? proxy.insertText("\u{1b}[D") : proxy.adjustTextPosition(byCharacterOffset: -1)
        case .right:
            state.terminal ? proxy.insertText("\u{1b}[C") : proxy.adjustTextPosition(byCharacterOffset: 1)
        case .up:
            state.terminal ? proxy.insertText("\u{1b}[A")
                 : proxy.adjustTextPosition(byCharacterOffset: TextNav.upOffset(before: proxy.documentContextBeforeInput ?? ""))
        case .down:
            state.terminal ? proxy.insertText("\u{1b}[B")
                 : proxy.adjustTextPosition(byCharacterOffset: TextNav.downOffset(
                     before: proxy.documentContextBeforeInput ?? "", after: proxy.documentContextAfterInput ?? ""))
        case .backspace:
            proxy.deleteBackward()
        case .forwardDelete:
            if state.terminal {
                proxy.insertText("\u{1b}[3~")
            } else if !(proxy.documentContextAfterInput ?? "").isEmpty {
                proxy.adjustTextPosition(byCharacterOffset: 1)
                proxy.deleteBackward()
            }
        case .ctrl:
            state.ctrl.toggle()
        }
    }

    /// Typing while the "+" editor is open goes into the draft, never into the host app. Returns false for keys that keep normal behavior (shift, layers, globe).
    private func editDraft(_ event: KeyEvent) -> Bool {
        func edit(_ change: (inout String) -> Void) {
            if state.draft!.editingPayload { change(&state.draft!.payload) } else { change(&state.draft!.label) }
        }
        switch event {
        case .char(let s):
            edit { $0 += state.shift == .off ? s : s.uppercased() }
            if state.shift == .once { state.shift = .off }
        case .space: edit { $0 += " " }
        case .backspace: edit { _ = $0.popLast() }
        case .ret: saveDraft()
        default: return false
        }
        return true
    }

    private func saveDraft() {
        guard let d = state.draft else { return }
        let label = d.label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return flash("Type a label first") }
        state.shortcuts.append(Shortcut(label: label, kind: .text,
                                        payload: d.payload.isEmpty ? Shortcut.inferPayload(from: label) : d.payload))
        state.draft = nil
        Store.shortcuts = state.shortcuts   // App Group writes need Full Access; without it the chip lasts this session only
        flash(hasFullAccess ? "Added \(label)" : "Added for now. Enable Full Access to keep it")
        autoCapitalize()
    }

    // MARK: - Virtual select-all
    // iOS gives keyboards no API to set the host's selection, so Ctrl+A arms a keyboard-side "all selected" state
    // and the next action (copy/cut/paste/delete/type) is applied to the whole document.

    /// Returns true if the event was applied to the virtual selection. Mode keys pass through; anything else cancels it.
    private func consumeSelectAll(_ event: KeyEvent) -> Bool {
        var code: UInt32?
        switch event {
        case .shift, .layer, .globe: return false
        case .char(let s):
            if state.ctrl, let ctl = Payload.control(for: Character(s)) {
                state.ctrl = false
                code = ctl.unicodeScalars.first!.value
            } else {
                replaceAll(with: state.shift == .off ? s : s.uppercased())
                if state.shift == .once { state.shift = .off }
                return true
            }
        case .space: replaceAll(with: " "); return true
        case .backspace: replaceAll(with: ""); return true
        case .shortcut(let s):
            switch s.kind {
            case .copy: code = 0x03
            case .paste: code = 0x16
            case .backspace, .forwardDelete: replaceAll(with: ""); return true
            case .ctrl: return false
            case .text:
                let out = Payload.decode(s.payload).unicodeScalars
                if out.count == 1 { code = out.first!.value }
            default: break
            }
        default: break
        }
        switch code {
        case 0x01: return true
        case 0x03, 0x18:
            guard hasFullAccess else { state.allSelected = false; flash("Enable Full Access for Copy"); return true }
            let cut = code == 0x18
            withAllText { [weak self] all in
                guard let self else { return }
                guard !all.isEmpty else { return self.flash("Nothing to copy") }
                UIPasteboard.general.string = all
                if cut { for _ in 0..<all.count { self.proxy.deleteBackward() } }
                log.debug("select-all \(cut ? "cut" : "copy", privacy: .public) chars=\(all.count)")
                self.flash(cut ? "Cut all (\(all.count) chars)" : "Copied all (\(all.count) chars)")
            }
        case 0x16:
            guard hasFullAccess, let clip = UIPasteboard.general.string else {
                state.allSelected = false
                flash(hasFullAccess ? "Clipboard empty" : "Enable Full Access for Paste")
                return true
            }
            replaceAll(with: clip)
        default:
            state.allSelected = false
            return false
        }
        return true
    }

    private func replaceAll(with text: String) {
        withAllText { [weak self] all in
            guard let self else { return }
            for _ in 0..<all.count { self.proxy.deleteBackward() }
            if !text.isEmpty { self.proxy.insertText(text) }
            self.autoCapitalize()
        }
    }

    private func withAllText(_ body: @escaping @MainActor (String) -> Void) {
        state.allSelected = false
        Task { @MainActor in body(await readAllText()) }
    }

    /// Reads the whole document by walking the cursor: the proxy only exposes a window of text around it.
    /// Leaves the cursor at the end. shortcut: the proxy's context updates asynchronously, so each step waits
    /// up to ~150ms for it to change; a host slower than that could make a chunk read twice.
    private func readAllText() async -> String {
        func settle(_ old: String, _ read: () -> String?) async {
            for _ in 0..<10 where (read() ?? "") == old { try? await Task.sleep(for: .milliseconds(15)) }
        }
        for _ in 0..<500 {
            let after = proxy.documentContextAfterInput ?? ""
            if after.isEmpty { break }
            proxy.adjustTextPosition(byCharacterOffset: after.count)
            await settle(after) { proxy.documentContextAfterInput }
        }
        var text = ""
        for _ in 0..<500 {
            let before = proxy.documentContextBeforeInput ?? ""
            if before.isEmpty { break }
            text = before + text
            proxy.adjustTextPosition(byCharacterOffset: -before.count)
            await settle(before) { proxy.documentContextBeforeInput }
        }
        proxy.adjustTextPosition(byCharacterOffset: text.count)
        await settle("") { proxy.documentContextBeforeInput }
        return text
    }

    private func autoCapitalize() {
        guard state.shift != .locked, state.layer == .letters, state.draft == nil else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        let cap: Bool = switch proxy.autocapitalizationType ?? .sentences {
        case .allCharacters: true
        case .words: before.isEmpty || before.last!.isWhitespace
        case .sentences:
            before.isEmpty || before.hasSuffix("\n")
                || (before.hasSuffix(" ") && [".", "!", "?"].contains(before.trimmingCharacters(in: .whitespaces).last))
        default: false
        }
        state.shift = cap ? .once : .off
    }

    private func flash(_ message: String) {
        state.toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if state.toast == message { state.toast = nil }
        }
    }
}

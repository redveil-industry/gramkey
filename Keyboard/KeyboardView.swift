import SwiftUI

enum KeyEvent {
    case char(String), backspace, space, ret, shift, toggleTerminal, layer(KeyboardState.Layer), globe, shortcut(Shortcut)
    case edit(EditAction), suggestion(String)
}

/// Hold-space menu items.
enum EditAction: String, CaseIterable { case selectAll = "Select All", copy = "Copy", cut = "Cut", paste = "Paste" }

@MainActor
final class KeyboardState: ObservableObject {
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, once, locked }

    @Published var layer = Layer.letters
    @Published var shift = Shift.off
    @Published var ctrl = false
    @Published var terminal = false   // raw control bytes/ANSI (SSH) vs. text-editing commands
    @Published var allSelected = false   // virtual select-all armed by Ctrl+A (iOS can't select in the host)
    @Published var hold: Hold?            // hold-space popout panel, tracking the finger
    @Published var suggestionsOn = false  // hidden in Terminal mode and fields with autocorrection off
    @Published var word = ""              // word being typed, left of the cursor
    @Published var suggestions: [String] = []   // or next-word predictions when `word` is empty
    @Published var correction: String?          // what space will autocorrect `word` to (highlighted)
    @Published var isDark = false
    @Published var needsGlobe = true
    @Published var returnLabel: String?
    @Published var shortcuts: [Shortcut] = []
    @Published var toast: String?
    /// Non-nil while the in-keyboard "+" editor is open; key presses edit it instead of the host text.
    @Published var draft: Draft?
    var send: (KeyEvent) -> Void = { _ in }
    var haptic: () -> Void = {}

    struct Hold { var start: CGPoint; var current: CGPoint; var index: Int? }
    struct Draft { var label = ""; var payload = ""; var editingPayload = false }
}

struct KeyboardView: View {
    static let barHeight: CGFloat = 46
    static let rowHeight: CGFloat = 54
    static let suggestHeight: CGFloat = 40
    static let totalHeight = barHeight + rowHeight * 4
    static func height(suggestions: Bool) -> CGFloat { totalHeight + (suggestions ? suggestHeight : 0) }

    // Hold-space panel geometry (in the "keys" coordinate space)
    static let cellW: CGFloat = 82, cellH: CGFloat = 46, panelPad: CGFloat = 5
    static var panelW: CGFloat { cellW * CGFloat(EditAction.allCases.count) + panelPad * 2 }
    static func panelLeft(_ h: KeyboardState.Hold, width: CGFloat) -> CGFloat {
        min(max(h.start.x - panelW / 2, 0), width - panelW)
    }
    /// Nothing is highlighted until the finger actually slides, so a plain hold + release cancels.
    static func holdIndex(_ h: KeyboardState.Hold, width: CGFloat) -> Int? {
        guard abs(h.current.x - h.start.x) > 10 || abs(h.current.y - h.start.y) > 10 else { return nil }
        let i = Int(((h.current.x - panelLeft(h, width: width) - panelPad) / cellW).rounded(.down))
        return min(max(i, 0), EditAction.allCases.count - 1)
    }

    @ObservedObject var state: KeyboardState
    private var p: Palette { Palette(dark: state.isDark) }

    var body: some View {
        VStack(spacing: 0) {
            if state.draft != nil {
                DraftBar(state: state)
            } else if state.allSelected {
                SelectAllBar(state: state)
            } else {
                ShortcutBar(state: state)
            }
            if state.suggestionsOn { SuggestionBar(state: state) }
            GeometryReader { geo in
                let u = geo.size.width / 10   // one letter-key slot, gaps included
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        switch state.layer {
                        case .letters: letters(u)
                        case .numbers: symbolRows(u, top: "1234567890", mid: "-/:;()$&@\"", toggle: ("#+=", .symbols))
                        case .symbols: symbolRows(u, top: "[]{}#%^*+=", mid: "_\\|~<>€£¥•", toggle: ("123", .numbers))
                        }
                        bottomRow(u)
                    }
                    if let h = state.hold { holdPanel(h, width: geo.size.width) }
                }
                .coordinateSpace(.named("keys"))
            }
            .frame(height: Self.rowHeight * 4)
        }
        .padding(.horizontal, 3)
        .overlay(alignment: .top) { toast }
    }

    /// Hold-space popout, styled like iOS's long-press accent panel: a raised tray of keys over the row above.
    private func holdPanel(_ h: KeyboardState.Hold, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(EditAction.allCases.enumerated()), id: \.element) { i, a in
                Text(a.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(h.index == i && !p.dark ? .white : p.text)
                    .frame(width: Self.cellW, height: Self.cellH)
                    .background(RoundedRectangle(cornerRadius: 9).fill(h.index == i ? p.highlight : .clear))
            }
        }
        .padding(Self.panelPad)
        .background(RoundedRectangle(cornerRadius: 14).fill(p.popout).shadow(color: .black.opacity(0.35), radius: 10, y: 3))
        .offset(x: Self.panelLeft(h, width: width), y: Self.rowHeight * 3 - Self.cellH - Self.panelPad * 2 - 4)
        .allowsHitTesting(false)
    }

    // MARK: Rows

    @ViewBuilder private func letters(_ u: CGFloat) -> some View {
        charRow("qwertyuiop", u)
        charRow("asdfghjkl", u)
        HStack(spacing: 0) {
            Key(style: state.shift == .off ? .special : .active, p: p, action: { state.send(.shift) }) {
                Image(systemName: state.shift == .locked ? "capslock.fill" : state.shift == .once ? "shift.fill" : "shift")
            }
            .frame(width: u * 1.4)
            Spacer(minLength: 0)
            ForEach(Array("zxcvbnm").map(String.init), id: \.self) { charKey($0).frame(width: u) }
            Spacer(minLength: 0)
            backspace.frame(width: u * 1.4)
        }
        .frame(height: Self.rowHeight)
    }

    @ViewBuilder private func symbolRows(_ u: CGFloat, top: String, mid: String,
                                         toggle: (String, KeyboardState.Layer)) -> some View {
        charRow(top, u)
        charRow(mid, u)
        HStack(spacing: 0) {
            Key(style: .special, p: p, action: { state.send(.layer(toggle.1)) }) { Text(toggle.0).font(.system(size: 16)) }
                .frame(width: u * 1.4)
            Spacer(minLength: 0)
            ForEach([".", ",", "?", "!", "'"], id: \.self) { charKey($0).frame(width: u * 1.4) }
            Spacer(minLength: 0)
            backspace.frame(width: u * 1.4)
        }
        .frame(height: Self.rowHeight)
    }

    private func bottomRow(_ u: CGFloat) -> some View {
        HStack(spacing: 0) {
            Key(style: .special, p: p, action: { state.send(.layer(state.layer == .letters ? .numbers : .letters)) }) {
                Text(state.layer == .letters ? "123" : "ABC").font(.system(size: 16))
            }
            .frame(width: u * 1.25)
            if state.needsGlobe {
                Key(style: .special, p: p, action: { state.send(.globe) }) { Image(systemName: "globe") }
                    .frame(width: u * 1.25)
            }
            Key(style: .letter, p: p, onHold: state.draft == nil ? { holdSpace($0, width: u * 10) } : nil,
                action: { state.send(.space) }) { Text("space").font(.system(size: 16)) }
            let returnLabel = state.draft != nil ? "add" : state.returnLabel
            Key(style: returnLabel == nil ? .special : .accent, p: p, action: { state.send(.ret) }) {
                if let label = returnLabel { Text(label).font(.system(size: 16)) } else { Image(systemName: "return") }
            }
            .frame(width: u * 2.5)
        }
        .frame(height: Self.rowHeight)
    }

    private func holdSpace(_ event: HoldEvent, width: CGFloat) {
        switch event {
        case .began(let pt):
            state.hold = .init(start: pt, current: pt, index: nil)
            state.haptic()
        case .moved(let pt):
            guard var h = state.hold else { return }
            h.current = pt
            let i = Self.holdIndex(h, width: width)
            if i != h.index, i != nil { state.haptic() }
            h.index = i
            state.hold = h
        case .ended:
            if let i = state.hold?.index { state.send(.edit(EditAction.allCases[i])) }
            state.hold = nil
        }
    }

    private func charRow(_ chars: String, _ u: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(chars).map(String.init), id: \.self) { charKey($0).frame(width: u) }
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight)
    }

    private func charKey(_ c: String) -> some View {
        let shown = state.shift == .off ? c : c.uppercased()
        return Key(style: .letter, p: p, callout: shown, action: { state.send(.char(c)) }) {
            Text(shown).font(.system(size: 25))
        }
    }

    private var backspace: some View {
        Key(style: .special, p: p, repeats: true, action: { state.send(.backspace) }) { Image(systemName: "delete.left") }
    }

    @ViewBuilder private var toast: some View {
        if let msg = state.toast {
            Text(msg)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.75)))
                .foregroundStyle(.white)
                .padding(.top, Self.barHeight + 4)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Shortcut bar

struct ShortcutBar: View {
    @ObservedObject var state: KeyboardState
    private var p: Palette { Palette(dark: state.isDark) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { state.send(.toggleTerminal) } label: {
                    Image(systemName: "terminal").frame(minWidth: 44, minHeight: 34)
                }
                .buttonStyle(ChipStyle(p: p, active: state.terminal))
                .accessibilityLabel(state.terminal ? "Terminal mode on" : "Terminal mode off")
                ForEach(state.shortcuts) { s in Chip(shortcut: s, active: s.kind == .ctrl && state.ctrl, p: p) { state.send(.shortcut(s)) } }
                Button {
                    state.draft = .init()
                    state.shift = .off
                } label: {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 34)
                }
                .buttonStyle(ChipStyle(p: p, active: false))
                .accessibilityLabel("Add shortcut")
                .accessibilityIdentifier("addChip")
            }
            .padding(.horizontal, 3)
        }
        .noScrollEdgeEffect()
        .frame(height: KeyboardView.barHeight)
    }
}

/// Apple-style suggestion strip: "typed" · best · alternative. Candidates come from UITextChecker (on-device).
struct SuggestionBar: View {
    @ObservedObject var state: KeyboardState
    private var p: Palette { Palette(dark: state.isDark) }

    var body: some View {
        // typing: "typed" · correction (highlighted: space applies it) or best · alternative; after a space: predictions
        let typing = !state.word.isEmpty
        let values = state.draft != nil ? [] : typing
            ? [state.word] + (state.correction.map { [$0] } ?? []) + state.suggestions
            : state.suggestions
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                if i > 0 { Rectangle().fill(p.text.opacity(0.2)).frame(width: 0.5, height: 22) }
                if i < values.count {
                    let pending = typing && i == 1 && state.correction != nil
                    Button { state.send(.suggestion(values[i])) } label: {
                        Text(typing && i == 0 ? "\u{201C}\(values[i])\u{201D}" : values[i])
                            .font(.system(size: 16, weight: pending ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(p.text)
                            .padding(.horizontal, 10)
                            .frame(maxHeight: .infinity)
                            .background { if pending { RoundedRectangle(cornerRadius: 8).fill(p.letter).padding(.vertical, 5) } }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: KeyboardView.suggestHeight)
    }
}

/// Shown after Ctrl+A. The host app shows no highlight (iOS doesn't allow it), so this bar is the selection indicator.
struct SelectAllBar: View {
    @ObservedObject var state: KeyboardState
    private var p: Palette { Palette(dark: state.isDark) }

    var body: some View {
        HStack(spacing: 6) {
            Text("All selected")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.blue)
                .padding(.leading, 6)
            Spacer(minLength: 0)
            action("Copy") { state.send(.shortcut(Shortcut(label: "Copy", kind: .copy))) }
            action("Cut") { state.send(.shortcut(Shortcut(label: "Cut", kind: .text, payload: "^X"))) }
            action("Delete") { state.send(.backspace) }
            Button { state.allSelected = false } label: { Image(systemName: "xmark").frame(width: 34, height: 34) }
                .buttonStyle(ChipStyle(p: p, active: false))
                .accessibilityLabel("Cancel selection")
        }
        .padding(.horizontal, 3)
        .frame(height: KeyboardView.barHeight)
    }

    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Text(title).font(.system(size: 15, design: .monospaced)).padding(.horizontal, 12).frame(minHeight: 34) }
            .buttonStyle(ChipStyle(p: p, active: false))
    }
}

/// Replaces the bar while adding a chip: [✕] [Label] [Sends] [Add]. Keyboard keys type into the focused field.
struct DraftBar: View {
    @ObservedObject var state: KeyboardState
    private var p: Palette { Palette(dark: state.isDark) }

    var body: some View {
        let d = state.draft ?? .init()
        HStack(spacing: 6) {
            Button { state.draft = nil } label: { Image(systemName: "xmark").frame(width: 34, height: 34) }
                .buttonStyle(ChipStyle(p: p, active: false))
                .accessibilityLabel("Cancel")
            field(d.label, placeholder: "Label", active: !d.editingPayload) { state.draft?.editingPayload = false }
            field(d.payload, placeholder: d.label.isEmpty ? "Sends (auto)" : Shortcut.inferPayload(from: d.label),
                  active: d.editingPayload) { state.draft?.editingPayload = true }
            Button { state.send(.ret) } label: { Text("Add").padding(.horizontal, 12).frame(minHeight: 34) }
                .buttonStyle(ChipStyle(p: p, active: true))
        }
        .padding(.horizontal, 3)
        .frame(height: KeyboardView.barHeight)
    }

    private func field(_ text: String, placeholder: String, active: Bool, onTap: @escaping () -> Void) -> some View {
        let caret = Rectangle().fill(Color.blue).frame(width: 2, height: 18).opacity(active ? 1 : 0)
        return HStack(spacing: 1) {
            if text.isEmpty {
                caret
                Text(placeholder).foregroundStyle(p.text.opacity(0.4))
            } else {
                Text(text).foregroundStyle(p.text)
                caret
            }
        }
        .font(.system(size: 15, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.head)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(p.chip))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Color.blue : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private extension View {
    /// iOS 26 blurs ScrollView content at container edges; the bar sits flush with the keyboard's top edge, so every chip got blurred.
    @ViewBuilder func noScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectHidden(true, for: .all) } else { self }
    }
}

/// A Button (so the bar still scrolls) plus long-press auto-repeat for arrows/delete.
struct Chip: View {
    let shortcut: Shortcut
    let active: Bool
    let p: Palette
    let action: () -> Void
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            Text(shortcut.label)
                .font(.system(size: 15, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 44, minHeight: 34)
        }
        .buttonStyle(ChipStyle(p: p, active: active))
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 12) {
            guard shortcut.kind.repeats else { return }
            repeater = Task { @MainActor in
                while !Task.isCancelled {
                    action()
                    try? await Task.sleep(for: .milliseconds(70))
                }
            }
        } onPressingChanged: { pressing in
            if !pressing { repeater?.cancel(); repeater = nil }
        }
        .accessibilityLabel(shortcut.label)
    }
}

struct ChipStyle: ButtonStyle {
    let p: Palette
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Color.black : p.text)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(active ? .white : configuration.isPressed ? p.letter : p.chip))
    }
}

// MARK: - Key

enum HoldEvent { case began(CGPoint), moved(CGPoint), ended }

struct Key<Label: View>: View {
    enum Style { case letter, special, active, accent }

    let style: Style
    let p: Palette
    var repeats = false
    /// Letter shown in the popped-out bubble while pressed (Apple's key callout).
    var callout: String? = nil
    /// When set, `action` fires on release and holding reports finger positions (in the "keys" space) instead.
    var onHold: ((HoldEvent) -> Void)? = nil
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var pressed = false
    @State private var held = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        label()
            .foregroundStyle(style == .accent ? .white : style == .active && !p.dark ? .black : p.text)
            .font(.system(size: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .shadow(color: p.shadow, radius: 0, x: 0, y: 1)
            )
            .overlay { if pressed, let callout { bubble(callout) } }
            .padding(.horizontal, 3)
            .padding(.vertical, 5.5)
            .contentShape(Rectangle())   // padding is tappable too: no dead zones between keys, like Apple's
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("keys"))
                .onChanged { value in
                    if pressed {
                        if held { onHold?(.moved(value.location)) }
                        return
                    }
                    pressed = true
                    held = false
                    if let onHold {
                        let start = value.location
                        repeater = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            guard !Task.isCancelled else { return }
                            held = true
                            onHold(.began(start))
                        }
                        return
                    }
                    action()
                    guard repeats else { return }
                    repeater = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        while !Task.isCancelled {
                            action()
                            try? await Task.sleep(for: .milliseconds(80))
                        }
                    }
                }
                .onEnded { _ in
                    if let onHold { held ? onHold(.ended) : action() }
                    pressed = false
                    held = false
                    repeater?.cancel()
                    repeater = nil
                })
    }

    /// Enlarged copy of the key floating above it; stays within the key's own touch padding horizontally,
    /// so neighbours drawn later in the row never cover it.
    private func bubble(_ text: String) -> some View {
        GeometryReader { g in
            Text(text)
                .font(.system(size: 28))
                .foregroundStyle(p.text)
                .frame(width: g.size.width + 2, height: g.size.height)
                .background(RoundedRectangle(cornerRadius: 8).fill(p.letter).shadow(color: .black.opacity(0.25), radius: 3, y: 1))
                .position(x: g.size.width / 2, y: -g.size.height * 0.42)
        }
        .allowsHitTesting(false)
    }

    private var fill: Color {
        switch style {
        case .letter: pressed ? p.special : p.letter
        case .special: pressed ? p.letter : p.special
        case .active: p.dark ? p.letter : .white
        case .accent: .blue
        }
    }
}

struct Palette {
    let dark: Bool
    var letter: Color { dark ? Color(white: 0.42) : .white }
    var special: Color { dark ? Color(white: 0.27) : Color(red: 0.67, green: 0.70, blue: 0.74) }
    var chip: Color { dark ? Color(white: 0.20) : Color(red: 0.80, green: 0.82, blue: 0.85) }
    var text: Color { dark ? .white : .black }
    var popout: Color { dark ? Color(white: 0.33) : .white }
    var highlight: Color { dark ? Color(white: 0.55) : .blue }
    var shadow: Color { dark ? .black.opacity(0.4) : Color(white: 0.5).opacity(0.5) }
}

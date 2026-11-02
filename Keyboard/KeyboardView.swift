import SwiftUI

enum KeyEvent {
    case char(String), backspace, space, ret, shift, toggleTerminal, layer(KeyboardState.Layer), globe, shortcut(Shortcut)
}

@MainActor
final class KeyboardState: ObservableObject {
    enum Layer { case letters, numbers, symbols }
    enum Shift { case off, once, locked }

    @Published var layer = Layer.letters
    @Published var shift = Shift.off
    @Published var ctrl = false
    @Published var terminal = false   // raw control bytes/ANSI (SSH) vs. text-editing commands
    @Published var allSelected = false   // virtual select-all armed by Ctrl+A (iOS can't select in the host)
    @Published var isDark = false
    @Published var needsGlobe = true
    @Published var returnLabel: String?
    @Published var shortcuts: [Shortcut] = []
    @Published var toast: String?
    /// Non-nil while the in-keyboard "+" editor is open; key presses edit it instead of the host text.
    @Published var draft: Draft?
    var send: (KeyEvent) -> Void = { _ in }

    struct Draft { var label = ""; var payload = ""; var editingPayload = false }
}

struct KeyboardView: View {
    static let barHeight: CGFloat = 46
    static let rowHeight: CGFloat = 54
    static let totalHeight = barHeight + rowHeight * 4

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
            GeometryReader { geo in
                let u = geo.size.width / 10   // one letter-key slot, gaps included
                VStack(spacing: 0) {
                    switch state.layer {
                    case .letters: letters(u)
                    case .numbers: symbolRows(u, top: "1234567890", mid: "-/:;()$&@\"", toggle: ("#+=", .symbols))
                    case .symbols: symbolRows(u, top: "[]{}#%^*+=", mid: "_\\|~<>€£¥•", toggle: ("123", .numbers))
                    }
                    bottomRow(u)
                }
            }
            .frame(height: Self.rowHeight * 4)
        }
        .padding(.horizontal, 3)
        .overlay(alignment: .top) { toast }
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
            Key(style: .letter, p: p, action: { state.send(.space) }) { Text("space").font(.system(size: 16)) }
            let returnLabel = state.draft != nil ? "add" : state.returnLabel
            Key(style: returnLabel == nil ? .special : .accent, p: p, action: { state.send(.ret) }) {
                if let label = returnLabel { Text(label).font(.system(size: 16)) } else { Image(systemName: "return") }
            }
            .frame(width: u * 2.5)
        }
        .frame(height: Self.rowHeight)
    }

    private func charRow(_ chars: String, _ u: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(chars).map(String.init), id: \.self) { charKey($0).frame(width: u) }
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight)
    }

    private func charKey(_ c: String) -> some View {
        Key(style: .letter, p: p, action: { state.send(.char(c)) }) {
            Text(state.shift == .off ? c : c.uppercased()).font(.system(size: 25))
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

struct Key<Label: View>: View {
    enum Style { case letter, special, active, accent }

    let style: Style
    let p: Palette
    var repeats = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var pressed = false
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
            .padding(.horizontal, 3)
            .padding(.vertical, 5.5)
            .contentShape(Rectangle())   // padding is tappable too: no dead zones between keys, like Apple's
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
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
                    pressed = false
                    repeater?.cancel()
                    repeater = nil
                })
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
    var shadow: Color { dark ? .black.opacity(0.4) : Color(white: 0.5).opacity(0.5) }
}

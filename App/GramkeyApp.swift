import SwiftUI

@main
struct GramkeyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var shortcuts = Store.shortcuts
    @State private var ansi = Store.arrowsSendANSI
    @State private var scratch = ""
    @FocusState private var tryFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    Text("Settings → General → Keyboard → Keyboards → Add New Keyboard → **Gramkey**, then tap Gramkey → **Allow Full Access** (required for Copy/Paste).")
                        .font(.callout)
                    Button("Open Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }

                Section("Try it") {
                    TextField("Type here…", text: $scratch, axis: .vertical).lineLimit(3...8)
                        .focused($tryFocused)
                        // `-focusTry` launch arg: open with the keyboard up (simulator screenshots / demos)
                        .task {
                            guard ProcessInfo.processInfo.arguments.contains("-focusTry") else { return }
                            try? await Task.sleep(for: .seconds(1))   // focus before the scene is active shows a caret but no keyboard
                            tryFocused = true
                        }
                }

                Section {
                    Toggle("Terminal mode", isOn: $ansi)
                } footer: {
                    Text("On (SSH / terminal apps): Ctrl, Esc, arrows and Del send raw control bytes and ANSI codes. Off (normal text): Ctrl+C/X/V copy/cut/paste, Ctrl+A selects all (then Copy/Cut/Delete/type), Ctrl+E jumps to line end, Ctrl+W/U/K delete word/to line start/to line end, Esc hides the keyboard. Also toggled by the >_ chip on the keyboard.")
                }

                Section("Shortcut bar") {
                    ForEach($shortcuts) { $s in
                        NavigationLink { ShortcutEditor(shortcut: $s) } label: {
                            HStack {
                                Text(s.label).monospaced()
                                Spacer()
                                Text(s.kind == .text ? s.payload : s.kind.title).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .onDelete { shortcuts.remove(atOffsets: $0) }
                    .onMove { shortcuts.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add shortcut", systemImage: "plus") {
                        shortcuts.append(Shortcut(label: "New", kind: .text, payload: ""))
                    }
                }

                Section {
                    Button("Reset shortcuts to defaults", role: .destructive) { shortcuts = Shortcut.defaults }
                }
            }
            .navigationTitle("Gramkey")
            .toolbar { EditButton() }
            .onChange(of: shortcuts) { _, new in Store.shortcuts = new }
            .onChange(of: ansi) { _, new in Store.arrowsSendANSI = new }
            // The keyboard's "+" can add chips while this app is open (e.g. in "Try it"); reload so we don't overwrite them.
            .onChange(of: scenePhase) { _, phase in if phase == .active { shortcuts = Store.shortcuts } }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                shortcuts = Store.shortcuts
            }
        }
        .safeAreaInset(edge: .bottom) {
            // `-previewKeyboard`: render the extension's real KeyboardView in-app (headless simulators hide software keyboards)
            if ProcessInfo.processInfo.arguments.contains("-previewKeyboard") { KeyboardPreview(shortcuts: shortcuts) }
        }
    }
}

struct KeyboardPreview: View {
    let shortcuts: [Shortcut]
    @Environment(\.colorScheme) private var scheme
    @StateObject private var state = KeyboardState()

    var body: some View {
        KeyboardView(state: state)
            .frame(height: KeyboardView.totalHeight)
            .padding(.bottom, 30)
            .background(scheme == .dark ? Color(white: 0.17) : Color(red: 0.82, green: 0.84, blue: 0.86))
            .onAppear { state.isDark = scheme == .dark; state.needsGlobe = false }
            .onChange(of: shortcuts, initial: true) { _, new in state.shortcuts = new }
    }
}

struct ShortcutEditor: View {
    @Binding var shortcut: Shortcut

    var body: some View {
        Form {
            TextField("Label", text: $shortcut.label)
            Picker("Action", selection: $shortcut.kind) {
                ForEach(Shortcut.Kind.allCases) { Text($0.title).tag($0) }
            }
            if shortcut.kind == .text {
                Section {
                    TextField("Sends", text: $shortcut.payload)
                        .monospaced()
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Bytes", value: Payload.decode(shortcut.payload).unicodeScalars
                        .map { $0.value < 0x20 || $0.value == 0x7f ? String(format: "0x%02X", $0.value) : String($0) }
                        .joined(separator: " "))
                } footer: {
                    Text("Escapes: \\e = Esc, \\n, \\t, \\r, \\\\, ^C = Ctrl+C (any ^A–^Z, ^[ …). Plain text is inserted as-is, e.g. a snippet or command.")
                }
            }
        }
        .navigationTitle(shortcut.label)
    }
}

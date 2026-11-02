# Gramkey

iOS custom keyboard: Apple-style QWERTY plus a scrollable, user-editable shortcut bar (Copy, Paste, Esc, Tab, Shift+Tab, arrows, ⌫/Del, sticky Ctrl, Ctrl+C/D/Z/L/R/A/E/W/U, and any text/escape sequence you define).

```
App/        container app: setup steps, Terminal-mode toggle, shortcut editor
Keyboard/   UIInputViewController + SwiftUI keyboard
Shared/     Shortcut model, escape decoding, up/down cursor math, App Group store
Tests/      unit tests for the pure logic
project.yml XcodeGen spec (xcodeproj is generated, not hand-edited)
```

## Quick-add from the keyboard
Tap **+** at the end of the bar. Type a label, and optionally what it sends, then tap **Add** (or return). The keyboard keys type into the editor, not the app. If you leave *Sends* empty, `Ctrl+O` sends `^O`; any other label sends its own text. Saving needs Full Access; without it the chip lasts only until the keyboard reloads. Editing and deleting still happen in the app.

## Build & run

```bash
xcodegen generate
open Gramkey.xcodeproj
```

1. Set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode, Signing & Capabilities, for both targets). Then regenerate. The App Group `group.com.redveil.gramkey` must be registered to your team; change the ID in `project.yml` **and** `Shared/Shortcut.swift` if it is taken.
2. Run the **Gramkey** scheme on a device or simulator.
3. In Settings, go to General → Keyboard → Keyboards → Add New Keyboard → Gramkey, then turn on **Allow Full Access**.
4. Tests: `xcodebuild -scheme Gramkey -destination 'platform=iOS Simulator,name=iPhone 16' test`

## How keys reach the host app

The iOS keyboard API only offers `insertText`, `deleteBackward` and `adjustTextPosition`. There are no real key events.

Toggle with the **>_** chip at the start of the bar (or in the app).

| Key | Text mode | Terminal mode |
|---|---|---|
| ← → | move cursor | `ESC[D` / `ESC[C` |
| ↑ ↓ | move to the same column on the previous/next line (computed) | `ESC[A` / `ESC[B` |
| Del | forward delete | `ESC[3~` |
| Ctrl+C / X / V | copy / cut / paste | `0x03` / `0x18` / `0x16` |
| Ctrl+A | virtual select-all: the next Copy/Cut/Paste/Delete/typing applies to the whole text (the host shows no highlight; iOS can't select from a keyboard) | `0x01` |
| Ctrl+E, W / U / K | line end; delete word / to line start / to line end | raw control byte |
| Esc | hide keyboard | `0x1B` |
| Ctrl+Z, Ctrl+R, Shift+Tab… | toast: needs Terminal mode (no iOS API for undo) | raw bytes |
| Ctrl (sticky) | next letter typed becomes its control char | same |

SSH/terminal apps (Blink, Termius, a web terminal) forward these to the PTY. Ordinary text fields will show them as invisible characters. That is an iOS limitation, not a bug.

## Known limits
- No emoji key or dictation mic: iOS doesn't expose them to third-party keyboards. The system globe/mic row still appears on Face ID iPhones.
- iOS disables third-party keyboards in secure (password) fields and in some apps (phone pads).
- Copy only works when the host app exposes `selectedText`. Some apps don't.
- No autocorrect or predictions yet. There is no key-press popup callout yet.

## Security posture
Keyboards see every keystroke. This one has **no networking, no analytics, no logging**, and it persists only the shortcut config in the App Group. Full Access is requested only for `UIPasteboard`. Keep it that way: adding any network call to the extension changes the threat model.

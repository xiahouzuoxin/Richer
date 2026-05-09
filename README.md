# Richer

A Bob-style macOS writing assistant. Two core actions:

- **Refine** typed or selected text — Grammar Fix / Polish / Professional / Concise / Casual
- **Translate** — auto-detect source, swap between configured primary/secondary languages (default: English ↔ Chinese)

The input window adopts a Bob-style **card paradigm**: each card pins one **provider** to one **action** (e.g. "Polish · Claude", "Translate · GLM"). Click a card and it streams its result inline. Run multiple providers/actions in parallel to compare results side-by-side.

UI is fully localized in English and Simplified Chinese; switch via Settings → General → Language.

## Quickstart

### Prerequisites

- macOS 14+ (Sonoma) or later — works on macOS 26
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Generate the Xcode project

```sh
xcodegen generate
open Richer.xcodeproj
```

Build & run from Xcode (⌘R), or build a release version (see [Install](#install) below).

### First run

1. The app appears in the menu bar (no Dock icon by default).
2. **Settings → Providers** → add an LLM provider:
   - Pick a Kind (Claude / OpenAI / DeepSeek / Qwen / Zhipu GLM / OpenAI-compatible / Ollama).
   - Paste your API key — stored in macOS Keychain.
   - Free-tier hints surface inline (e.g. `glm-4-flash` is free, `qwen-turbo` has a free quota).
3. **Settings → Cards** → click **Suggested** to seed three default cards (Polish · Claude, Grammar Fix · Claude, Translate · Claude). Add more via `+`. Toggle individual cards on/off without losing config.
4. Open the input window via the menu bar **Open Input Window** or the global hotkey (default `⌥Space`).
5. **Settings → Hotkeys** — defaults:
   - `⌥⇧R` — refine current selection (popup)
   - `⌥⇧T` — translate current selection (popup with Auto/EN/ZH buttons)
   - `⌥Space` — open the input window
6. Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility). The selection-hotkey workflow needs it to synthesize `⌘C` against the focused app.

## Features

- **Card-per-(provider × action)** input window. Click to expand, stream tokens inline, run several in parallel.
- **Per-card enable/disable toggle**. Hide cards without deleting them.
- **Auto-hide on click outside** (input window). State is preserved — re-open and your typed text and streamed results are still there. Pin (📌 top-left) keeps it on top.
- **Selection popup** (Bob-style) with Auto / →EN / →ZH language switch buttons. Doesn't steal focus from the source app.
- **Streaming** via `URLSession.bytes(for:)`. Dismissing/collapsing cancels the in-flight request immediately.
- **Multi-provider**: Claude, OpenAI, DeepSeek, Qwen DashScope, Zhipu GLM, any OpenAI-compatible endpoint, Ollama (local).
- **History** persisted with SwiftData (Settings → History). Each successful run is logged; click to copy or re-run.
- **Localization**: English + 简体中文 via String Catalogs. Picker in Settings → General to override the system language.
- **Custom app icon** + monochrome menu-bar icon, generated reproducibly from `tools/GenerateIcon.swift`.

## Project structure

```
Richer/
  App/                 # @main, AppDelegate, Coordinator
  Core/
    Input/             # hotkeys (KeyboardShortcuts), selection capture (⌘C trick + AX fallback)
    LLM/               # protocol + streaming + per-provider adapters
    Prompting/         # shared prompt templates
    Keychain/          # API-key storage
    Permissions/       # Accessibility check
  Features/
    Popup/             # NSPanel + SwiftUI popup (selection-hotkey)
    InputWindow/       # NSPanel + SwiftUI input window with cards
    Cards/             # ActionCard model, store, view models, CardRow
    Refine/            # modes + service
    Translate/         # NLLanguageRecognizer + service
    History/           # SwiftData @Model + view
    Settings/          # tabbed Settings scene
  Resources/
    Info.plist
    Assets.xcassets    # app icon + menu bar icon
    Localizable.xcstrings
tools/
  GenerateIcon.swift   # regenerates all icon PNGs
```

## Install

The app is **unsigned** (signed-to-run-locally) and runs **outside the App Store sandbox** — that's required for the pasteboard-based selection capture to work. Treat it as a personal tool you build for your own machine.

### Quick install (build a Release version, drop into /Applications)

```sh
# from the repo root
xcodegen generate

xcodebuild \
  -project Richer.xcodeproj \
  -scheme Richer \
  -configuration Release \
  -derivedDataPath build \
  build

# the .app lands here:
ls build/Build/Products/Release/Richer.app

# install
rm -rf /Applications/Richer.app   # optional, removes a previous copy
cp -R build/Build/Products/Release/Richer.app /Applications/
open /Applications/Richer.app
```

### After the first launch from /Applications

1. **Re-grant Accessibility**: System Settings → Privacy & Security → Accessibility → remove any old "Richer" entry → drag `/Applications/Richer.app` in (or click the `+` and pick it). Make sure the toggle is on. Why: the Release build at `/Applications/Richer.app` has a different code-signing identity than the Debug builds in `~/Library/Developer/Xcode/DerivedData/...`, so macOS treats it as a separate app for permission purposes.
2. **Configure your provider(s)** again (the keychain entries from a Debug-signed copy don't carry over to a different signing identity).
3. **Auto-start at login** (optional): System Settings → General → Login Items → click `+` under "Open at Login" → pick `/Applications/Richer.app`.

### Refresh the icon if it looks stale

macOS aggressively caches app icons. After replacing `/Applications/Richer.app`:

```sh
killall Dock
killall Finder
```

### Updating

Re-run the install commands above. The keychain and SwiftData history are stored under your user account (not inside the bundle), so they survive a re-install — you don't lose providers, cards, or history.

### Distributing to other people (optional)

For personal use the steps above are enough. To give the app to other Macs without them having to disable Gatekeeper, you'd need:

- An Apple Developer ID Application certificate
- Sign the build: `codesign --force --options runtime --sign "Developer ID Application: …" Richer.app`
- Notarize: `xcrun notarytool submit Richer.app …`
- Optionally wrap into a `.dmg` via `create-dmg` or `hdiutil`.

This isn't wired into the project yet — add a release script if you ever need it.

## Regenerating the icon

```sh
swift tools/GenerateIcon.swift
xcodegen generate          # so Xcode picks up any new image filenames
```

The script produces all `AppIcon.appiconset` sizes and the monochrome `MenuBarIcon.imageset`.

## Notes

- LLM prompt templates live in [Richer/Core/Prompting/DefaultPrompts.swift](Richer/Core/Prompting/DefaultPrompts.swift). Refine modes can also be overridden per-mode in Settings → Refine.
- Search in History is a simple `localizedStandardContains` over `originalText` and `resultText` — fine to ~10k entries.
- Provider keys are stored via the legacy macOS keychain (`SecItemAdd` without `kSecUseDataProtectionKeychain`) so they work on builds without the `keychain-access-groups` entitlement.
- The selection-popup uses `.nonactivatingPanel` and avoids `NSMenu` (so the source app keeps focus). The full language picker lives only on the input window, where the panel is allowed to activate.

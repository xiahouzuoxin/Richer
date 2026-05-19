# Richer

A free, Bob-style **macOS translation & writing assistant** that lives in the menu bar. Refine, translate, look up, **read aloud**, **dictate**, or **caption** any text — through the LLM provider and dictionary of your choice.

## Features

- **Refine** — Grammar · Polish · Professional · Concise · Casual
- **Translate** — auto-detect source, configurable primary/secondary languages
- **Dictionary** — Eudic + macOS dictionary, with one-click "add to wordbook"
- **Read aloud (TTS)** — Apple's system voices on any input or result
- **Dictate (STT)** — live on-device speech-to-text in the input window
- **Live captions** — floating subtitle bar that transcribes mic audio in real-time, you can use anywhere
- **Screen OCR** — capture any region, OCR with Vision, then route to refine/translate/dictionary

### Card paradigm

The input window pins one **provider** to one **action** per card (e.g. *Polish · Claude*, *Translate · GLM*). Run multiple cards in parallel and compare results.

![Input window](image/input-window.png)

### Selection popup

Highlight text in any app, hit a hotkey, and a popup appears next to the selection — without stealing focus from the source app.

![Selection popup](image/selection-popup.png)
![Dictionary](image/dictionary.png)

### Default hotkeys

| Hotkey | Action |
|---|---|
| `⌥⇧R` | Refine selection (popup) |
| `⌥⇧T` | Translate selection (popup) |
| `⌥⇧D` | Look up selection (popup) |
| `⌥⇧S` | Capture a screen region, OCR, then pick an action |
| `⌥Space` | Open the input window |

All rebindable in *Settings → Hotkeys*.

### Free LLM providers to get started

Richer is BYOK. A few providers in the kind list offer genuinely free models:

| Provider | What's free |
|---|---|
| **Zhipu GLM** | `glm-4-flash`, `glm-4-flash-x` — free for everyone |
| **OpenRouter** | Free tier — [openrouter.ai/openrouter/free](https://openrouter.ai/openrouter/free) |
| **Ollama** (local) | Fully local, no key. Point Richer at `http://localhost:11434`. |
| **Google Gemini** (via OpenAI-compat) | Free tier on `gemini-2.0-flash`. Base URL: `https://generativelanguage.googleapis.com/v1beta/openai/` |

> Free quotas shift over time — verify on the provider's pricing page.

## Install

### Download the prebuilt release

1. Grab `Richer-x.y.z.zip` from [Releases](https://github.com/xiahouzuoxin/Richer/releases).
2. Unzip and move `Richer.app` to `/Applications`.
3. The build is **unsigned**, so strip the quarantine flag once:

   ```sh
   xattr -d com.apple.quarantine /Applications/Richer.app
   open /Applications/Richer.app
   ```

   Or right-click → **Open** → **Open** in the dialog.

### First-run setup

1. Find the menu-bar icon (no Dock icon by default).
2. **Settings → Providers** — add an LLM provider; key is stored in the macOS Keychain.
3. **Settings → Cards** — click **Suggested** to seed three defaults, or add your own.
4. **Grant permissions** when prompted:
   - **Accessibility** — for `⌥⇧R / ⌥⇧T / ⌥⇧D` to read the current selection.
   - **Screen Recording** — for `⌥⇧S` OCR. *Restart Richer after granting.*
   - **Microphone + Speech Recognition** — for dictation and live captions.

### After replacing the app

- Re-grant **Accessibility** and **Screen Recording** — a new signing identity counts as a new app to macOS.
- Re-enter API keys — Keychain entries are bound to the signing identity.
- If the icon looks stale: `killall Dock; killall Finder`

> **Not on the Mac App Store** because the selection popup must synthesize `⌘C` against another app's process — that requires running outside the App Store sandbox.

## Develop

Requires macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Richer.xcodeproj          # ⌘R to build & run
```

Release build:

```sh
xcodebuild -project Richer.xcodeproj -scheme Richer \
  -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/Richer.app /Applications/
```

### Project layout

```
Richer/
  App/                 # @main, AppDelegate, Coordinator
  Core/
    Input/             # hotkeys, selection capture (⌘C trick + AX fallback)
    LLM/               # protocol + streaming + per-provider adapters
    Dictionary/        # Eudic + macOS Dictionary bridge
    OCR/               # Vision wrapper
    Capture/           # screen-region grabber
    Speech/            # SFSpeechRecognizer (STT) + AVSpeechSynthesizer (TTS)
    Prompting/         # shared prompt templates
    Keychain/          # API-key storage
    Permissions/       # Accessibility / Screen Recording / Mic / Speech
  Features/
    Popup/             # selection-hotkey panel
    InputWindow/       # input window with cards + dictation
    Caption/           # floating live-caption bar
    Cards/             # ActionCard model + view models
    Refine/ Translate/ Dictionary/
    Screenshot/        # region picker + post-OCR action bar
    History/ Settings/
  Resources/           # Info.plist, Assets, Localizable.xcstrings, entitlements
```

## Thanks

- [**Bob**](https://bobtranslate.com/) — the original macOS translation utility this takes inspiration from.

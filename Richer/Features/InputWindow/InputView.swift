import SwiftUI
import SwiftData
import Observation
import AppKit
import AVFoundation

@Observable
@MainActor
final class InputViewModel {
    var inputText: String = ""
    var pinned: Bool = false
    var sourceOverride: String? = nil    // nil = auto-detect
    var targetOverride: String? = nil    // nil = auto-select (use primary/secondary fallback)
    var sttLocale: String = InputViewModel.defaultSTTLocale()
    /// `nil` means follow the OS default input; a non-nil value pins AVAudioEngine to
    /// a specific microphone via its `AVCaptureDevice.uniqueID`.
    var sttDeviceUID: String? = nil
    var sttErrorMessage: String?

    let speechRecognizer = SpeechRecognizer()

    /// Text in the input field at the moment STT started. STT writes are placed AFTER
    /// this; the user's pre-existing input is never touched.
    private var sttBasePrefix: String = ""
    /// The longest STT transcription we've ever committed to `inputText`. We only ever
    /// extend this (new partials must be strict prefix-extensions of what's committed),
    /// so STT can never delete or rewrite characters already visible to the user.
    private var sttCommittedSuffix: String = ""

    let providerStore: ProviderStore
    let refineModeStore: RefineModeStore
    let translateSettings: TranslateSettings
    let actionCardStore: ActionCardStore

    private(set) var cardViewModels: [UUID: CardViewModel] = [:]

    init(
        providerStore: ProviderStore,
        refineModeStore: RefineModeStore,
        translateSettings: TranslateSettings,
        actionCardStore: ActionCardStore
    ) {
        self.providerStore = providerStore
        self.refineModeStore = refineModeStore
        self.translateSettings = translateSettings
        self.actionCardStore = actionCardStore
        rebuildViewModels()
    }

    var isRecording: Bool { speechRecognizer.isRecording }

    // MARK: - STT control

    func toggleDictation() {
        if speechRecognizer.isRecording {
            speechRecognizer.stop()
            return
        }
        sttErrorMessage = nil
        startDictationFlow()
    }

    private func startDictationFlow() {
        // Permission cascade: microphone first (low cost to check), then speech recognition.
        if !MicrophoneGuard.isTrusted {
            MicrophoneGuard.requestTrust { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startDictationFlow()
                    } else {
                        self.sttErrorMessage = SpeechRecognitionError.microphoneDenied.errorDescription
                    }
                }
            }
            return
        }
        if !SpeechRecognitionGuard.isTrusted {
            SpeechRecognitionGuard.requestTrust { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startDictationFlow()
                    } else {
                        self.sttErrorMessage = SpeechRecognitionError.speechRecognitionDenied.errorDescription
                    }
                }
            }
            return
        }
        sttBasePrefix = inputText
        sttCommittedSuffix = ""
        speechRecognizer.start(
            locale: sttLocale,
            deviceUID: sttDeviceUID,
            onPartial: { [weak self] partial in
                self?.applySTTResult(partial)
            },
            onFinal: { [weak self] final in
                guard let self else { return }
                self.applySTTResult(final)
                self.sttBasePrefix = ""
                self.sttCommittedSuffix = ""
                if let recognizerError = self.speechRecognizer.lastError {
                    self.sttErrorMessage = recognizerError
                }
            }
        )
    }

    /// Apply an SFSpeech transcription. The contract:
    ///
    /// 1. **User content is sacred.** The `sttBasePrefix` (what was in the field when
    ///    dictation started) and any text the user typed *after* our last STT write
    ///    are both preserved verbatim across every update.
    /// 2. **SFSpeech may refine its own portion freely.** Partials are not strictly
    ///    monotonic — the recognizer revises earlier guesses as more audio arrives
    ///    ("hi there" → "high there", number normalization, homophone correction).
    ///    Forcing prefix-extension would kill STT the moment the recognizer second-
    ///    guesses itself; instead we always write the latest transcription into the
    ///    STT slot. The user's content around it stays put.
    /// 3. **Never write empty.** Protects against premature `stop()` finalizing with
    ///    no recognized audio.
    /// 4. **Bail on manual edits inside the STT portion.** If the user has clearly
    ///    touched the dictated text (the expected prefix no longer matches), stop
    ///    contributing for this session rather than fight their cursor.
    private func applySTTResult(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let expected = compose(prefix: sttBasePrefix, suffix: sttCommittedSuffix)
        let userTail: String
        if inputText.hasPrefix(expected) {
            userTail = String(inputText.dropFirst(expected.count))
        } else {
            return
        }

        sttCommittedSuffix = trimmed
        let newComposed = compose(prefix: sttBasePrefix, suffix: trimmed)
        inputText = newComposed + userTail
    }

    private func compose(prefix: String, suffix: String) -> String {
        if prefix.isEmpty { return suffix }
        if suffix.isEmpty { return prefix }
        let needsSpace = !prefix.hasSuffix(" ") && !prefix.hasSuffix("\n")
        return prefix + (needsSpace ? " " : "") + suffix
    }

    private static func defaultSTTLocale() -> String {
        let base = Locale.current.language.languageCode?.identifier ?? "en"
        switch base {
        case "zh":
            return (Locale.current.language.script?.identifier == "Hant") ? "zh-TW" : "zh-CN"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "it": return "it-IT"
        case "ru": return "ru-RU"
        case "pt": return "pt-BR"
        default: return "en-US"
        }
    }

    func rebuildViewModels() {
        var next: [UUID: CardViewModel] = [:]
        for card in enabledCards {
            // Reuse the existing view model only if the card's content hasn't changed.
            // CardViewModel snapshots `card` at init, so any edit (action, provider,
            // refine mode) needs a fresh view model to render correctly.
            if let existing = cardViewModels[card.id], existing.card == card {
                next[card.id] = existing
            } else {
                next[card.id] = CardViewModel(
                    card: card,
                    providerStore: providerStore,
                    refineModeStore: refineModeStore,
                    translateSettings: translateSettings
                )
            }
        }
        cardViewModels = next
    }

    var enabledCards: [ActionCard] {
        actionCardStore.cards.filter { $0.enabled }
    }

    func cancelAll() {
        for vm in cardViewModels.values { vm.cancel() }
    }

    func resetAllResults() {
        for vm in cardViewModels.values {
            vm.collapse()
            vm.reset()
        }
    }

    var hasTranslateCard: Bool {
        enabledCards.contains { card in
            if case .translate = card.action { return true } else { return false }
        }
    }
}

enum STTLocaleOption: CaseIterable, Identifiable {
    case enUS, zhCN, zhTW, jaJP, koKR, esES, frFR, deDE

    var id: String { code }
    var code: String {
        switch self {
        case .enUS: "en-US"
        case .zhCN: "zh-CN"
        case .zhTW: "zh-TW"
        case .jaJP: "ja-JP"
        case .koKR: "ko-KR"
        case .esES: "es-ES"
        case .frFR: "fr-FR"
        case .deDE: "de-DE"
        }
    }
    var label: String {
        switch self {
        case .enUS: "English"
        case .zhCN: "简体中文"
        case .zhTW: "繁體中文"
        case .jaJP: "日本語"
        case .koKR: "한국어"
        case .esES: "Español"
        case .frFR: "Français"
        case .deDE: "Deutsch"
        }
    }
}

struct InputView: View {
    @Bindable var viewModel: InputViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    var onClose: () -> Void
    var onPinChanged: (Bool) -> Void
    var onOpenHistory: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            inputBlock
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            if viewModel.hasTranslateCard {
                languageRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            cardsList
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(minWidth: 420, idealWidth: 480)
        .frame(minHeight: 320)
        .background(.regularMaterial)
        .onChange(of: viewModel.inputText) { _, _ in
            viewModel.resetAllResults()
        }
        .onChange(of: viewModel.actionCardStore.cards) { _, _ in
            viewModel.rebuildViewModels()
        }
        .onDisappear {
            viewModel.cancelAll()
        }
    }

    // MARK: - Top toolbar

    private var topToolbar: some View {
        HStack(spacing: 0) {
            iconButton(
                systemName: viewModel.pinned ? "pin.fill" : "pin",
                help: "Keep window on top"
            ) {
                viewModel.pinned.toggle()
                onPinChanged(viewModel.pinned)
            }
            .foregroundStyle(viewModel.pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            Spacer()

            iconButton(systemName: "arrow.clockwise", help: "Re-run expanded cards") {
                runExpandedOrAll()
            }
            iconButton(systemName: "clock.arrow.circlepath", help: "History") {
                onOpenHistory()
            }
            iconButton(systemName: "switch.2", help: "Settings") {
                openSettings()
            }
            iconButton(systemName: "xmark", help: "Close") {
                onClose()
            }
        }
    }

    /// Microphone label shown in the listening status line. If the user pinned a
    /// specific device in the chevron menu, show its name. Otherwise show whatever
    /// the OS has set as the default input (re-read each render, so the label updates
    /// if the user changes it in System Settings → Sound → Input).
    private var activeMicName: String {
        if let uid = viewModel.sttDeviceUID,
           let picked = AudioDeviceList.availableMicrophones().first(where: { $0.uniqueID == uid }) {
            return picked.name
        }
        return AVCaptureDevice.default(for: .audio)?.localizedName
            ?? String(localized: "system default mic")
    }

    // MARK: - Dictation control (mic toggle + locale chevron)

    private var dictationControl: some View {
        HStack(spacing: 2) {
            iconButton(
                systemName: viewModel.isRecording ? "mic.fill" : "mic",
                help: viewModel.isRecording ? "Stop dictating" : "Dictate"
            ) {
                viewModel.toggleDictation()
            }
            .foregroundStyle(viewModel.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))

            Menu {
                Section("Language") {
                    ForEach(STTLocaleOption.allCases) { option in
                        Button {
                            viewModel.sttLocale = option.code
                        } label: {
                            if viewModel.sttLocale == option.code {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                }
                Section("Microphone") {
                    Button {
                        viewModel.sttDeviceUID = nil
                    } label: {
                        if viewModel.sttDeviceUID == nil {
                            Label("System default", systemImage: "checkmark")
                        } else {
                            Text("System default")
                        }
                    }
                    ForEach(AudioDeviceList.availableMicrophones()) { device in
                        Button {
                            viewModel.sttDeviceUID = device.uniqueID
                        } label: {
                            if viewModel.sttDeviceUID == device.uniqueID {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 26)
                    .contentShape(.rect)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(viewModel.isRecording)
            .help("Dictation language & microphone")
        }
    }

    // MARK: - Input block

    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RicherTextEditor(
                    text: $viewModel.inputText,
                    placeholder: "Type or paste text here…",
                    onSubmit: { runAllCards() }
                )
                .frame(minHeight: 50, maxHeight: 100)
                PlaceholderOverlay(text: "Type or paste text here…", isVisible: viewModel.inputText.isEmpty)
            }
            HStack(spacing: 8) {
                dictationControl

                let speaker = SpeechSynthesizer.shared
                let isReadingInput = speaker.isPlaying(viewModel.inputText)
                iconButton(
                    systemName: isReadingInput ? "speaker.fill" : "speaker.wave.2",
                    help: isReadingInput ? "Stop reading" : "Read aloud"
                ) {
                    speaker.toggle(viewModel.inputText)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundStyle(isReadingInput ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

                iconButton(systemName: "doc.on.doc", help: "Copy input") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.inputText, forType: .string)
                }
                .disabled(viewModel.inputText.isEmpty)
                Spacer()
                if let err = viewModel.sttErrorMessage {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(err)
                } else if viewModel.isRecording {
                    Text("Listening… · \(activeMicName)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(activeMicName)
                } else {
                    Text("Enter to run · Shift↵ for newline")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Language row

    private var languageRow: some View {
        @Bindable var translateSettings = viewModel.translateSettings
        return HStack(spacing: 10) {
            sourcePicker
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            targetPicker
        }
        .padding(8)
        .background(.thinMaterial, in: .rect(cornerRadius: 8))
    }

    private var sourcePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.sourceOverride ?? "auto" },
            set: { viewModel.sourceOverride = $0 == "auto" ? nil : $0 }
        )) {
            Text("Auto-detect").tag("auto")
            ForEach(LanguageOptions.codes, id: \.self) { code in
                Text(LanguageDetector.displayName(for: code)).tag(code)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetPicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.targetOverride ?? "auto" },
            set: { viewModel.targetOverride = $0 == "auto" ? nil : $0 }
        )) {
            Text("Auto (en ↔ zh)").tag("auto")
            ForEach(LanguageOptions.codes, id: \.self) { code in
                Text(LanguageDetector.displayName(for: code)).tag(code)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Cards list

    private var cardsList: some View {
        Group {
            if viewModel.enabledCards.isEmpty {
                emptyCardsState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.enabledCards) { card in
                            if let cardVM = viewModel.cardViewModels[card.id] {
                                CardRow(
                                    viewModel: cardVM,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            cardVM.toggle(
                                                input: viewModel.inputText,
                                                targetOverride: viewModel.targetOverride,
                                                modelContext: modelContext
                                            )
                                        }
                                    },
                                    onRerun: {
                                        cardVM.run(
                                            input: viewModel.inputText,
                                            targetOverride: viewModel.targetOverride,
                                            modelContext: modelContext
                                        )
                                    }
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private var emptyCardsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            if viewModel.providerStore.providers.isEmpty {
                Text("Add a provider in Settings → Providers, then create cards.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("Create cards in Settings → Cards to start refining and translating.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: .rect(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func iconButton(systemName: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func runExpandedOrAll() {
        // Pressing the refresh / Enter implicitly ends dictation: the user is signaling
        // "I'm done speaking, act on this text now."
        if viewModel.isRecording {
            viewModel.toggleDictation()
        }
        let cards = viewModel.enabledCards
        let toRun = cards.filter { viewModel.cardViewModels[$0.id]?.isExpanded == true }
        let runList = toRun.isEmpty ? cards : toRun
        for card in runList {
            guard let cardVM = viewModel.cardViewModels[card.id] else { continue }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                cardVM.isExpanded = true
            }
            cardVM.run(
                input: viewModel.inputText,
                targetOverride: viewModel.targetOverride,
                modelContext: modelContext
            )
        }
    }

    /// Triggered by Enter on the input area. Expands all enabled cards and runs them in parallel.
    /// Also force-stops dictation if active — Enter means "input is done."
    private func runAllCards() {
        if viewModel.isRecording {
            viewModel.toggleDictation()
        }
        let trimmed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for card in viewModel.enabledCards {
            guard let cardVM = viewModel.cardViewModels[card.id] else { continue }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                cardVM.isExpanded = true
            }
            cardVM.run(
                input: viewModel.inputText,
                targetOverride: viewModel.targetOverride,
                modelContext: modelContext
            )
        }
    }
}

enum LanguageOptions {
    static let codes: [String] = [
        "en", "zh", "ja", "ko", "es", "fr", "de", "pt", "ru", "it"
    ]
}

@MainActor
final class InputWindowController {
    private var panel: InputPanel?
    private(set) var viewModel: InputViewModel?
    private var globalMonitor: Any?
    private var isPinned: Bool = false

    /// True when a panel + viewModel exist (window may be minimized or visible).
    /// Lets callers like the caption bar's "Send to input" know whether to reuse
    /// the existing input session or open a fresh one.
    var hasActiveSession: Bool { panel != nil && viewModel != nil }

    /// Append text to the active input window's text field, with a separator if the
    /// existing content is non-empty. No-op if no session is active.
    func appendToInput(_ text: String) {
        guard let viewModel else { return }
        let separator = viewModel.inputText.isEmpty ? "" : "\n"
        viewModel.inputText += separator + text
    }

    func show(viewModel: InputViewModel, modelContainer: ModelContainer, onOpenHistory: @escaping @MainActor () -> Void) {
        NSLog("[Richer] InputWindowController.show entered")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = panel {
            NSLog("[Richer] reusing existing input panel")
            existing.makeKeyAndOrderFront(nil)
            installOutsideMonitorIfNeeded()
            return
        }
        let onPinChanged: (Bool) -> Void = { [weak self] pinned in
            guard let self else { return }
            self.isPinned = pinned
            self.panel?.level = pinned ? .floating : .normal
        }
        let view = InputView(
            viewModel: viewModel,
            onClose: { [weak self] in
                Task { @MainActor in self?.close() }
            },
            onPinChanged: onPinChanged,
            onOpenHistory: onOpenHistory
        )
        .modelContainer(modelContainer)

        let hosting = NSHostingView(rootView: view)
        let panel = InputPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380))
        panel.title = "Richer"
        panel.contentView = hosting
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        self.viewModel = viewModel
        installOutsideMonitorIfNeeded()
        NSLog("[Richer] input panel shown at \(panel.frame)")
    }

    /// Full close: tear the panel down and let next show() create a fresh one.
    func close() {
        removeOutsideMonitor()
        panel?.orderOut(nil)
        panel = nil
        viewModel = nil
        let showDockIcon = UserDefaults.standard.bool(forKey: "richer.showDockIcon")
        if !showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Hide without destroying: next show() reuses the panel and preserves all state
    /// (typed text, expanded cards, streamed results).
    func minimize() {
        guard let panel else { return }
        removeOutsideMonitor()
        panel.orderOut(nil)
        let showDockIcon = UserDefaults.standard.bool(forKey: "richer.showDockIcon")
        if !showDockIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func installOutsideMonitorIfNeeded() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPinned else { return }
                self.minimize()
            }
        }
    }

    private func removeOutsideMonitor() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
    }
}

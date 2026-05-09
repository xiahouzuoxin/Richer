import SwiftUI
import SwiftData
import Observation
import AppKit

@Observable
@MainActor
final class InputViewModel {
    var inputText: String = ""
    var pinned: Bool = false
    var sourceOverride: String? = nil    // nil = auto-detect
    var targetOverride: String? = nil    // nil = auto-select (use primary/secondary fallback)

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

    func rebuildViewModels() {
        var next: [UUID: CardViewModel] = [:]
        for card in enabledCards {
            if let existing = cardViewModels[card.id] {
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
        .frame(width: 480)
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
                iconButton(systemName: "doc.on.doc", help: "Copy input") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.inputText, forType: .string)
                }
                .disabled(viewModel.inputText.isEmpty)
                Spacer()
                Text("Enter to run · Shift↵ for newline")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
    private func runAllCards() {
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
    private var globalMonitor: Any?
    private var isPinned: Bool = false

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
        installOutsideMonitorIfNeeded()
        NSLog("[Richer] input panel shown at \(panel.frame)")
    }

    /// Full close: tear the panel down and let next show() create a fresh one.
    func close() {
        removeOutsideMonitor()
        panel?.orderOut(nil)
        panel = nil
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

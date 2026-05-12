import AppKit
import Observation
import SwiftData

enum WriteIntent: Sendable, Equatable {
    case refine
    case translate
    case dictionary
}

@Observable
@MainActor
final class Coordinator {
    private let popupController = PopupWindowController()
    private let inputController = InputWindowController()
    private let captionController = CaptionWindowController()
    private let hotkeys = HotkeyManager()
    private let selection = SelectionCapture()
    private let regionController = ScreenshotRegionController()
    private let actionBarController = ActionBarController()
    let providerStore = ProviderStore()
    let refineModeStore = RefineModeStore()
    let translateSettings = TranslateSettings()
    let actionCardStore = ActionCardStore()
    var modelContainer: ModelContainer?

    func start() {
        hotkeys.register(
            onSelectionRefine: { [weak self] in self?.handleSelectionHotkey(intent: .refine) },
            onSelectionTranslate: { [weak self] in self?.handleSelectionHotkey(intent: .translate) },
            onSelectionDictionary: { [weak self] in self?.handleSelectionHotkey(intent: .dictionary) },
            onScreenshotOCR: { [weak self] in self?.handleScreenshotOCR() },
            onCaptionBar: { [weak self] in self?.openCaptionBar() },
            onInputWindow: { [weak self] in self?.openInputWindow(intent: .refine) }
        )
    }

    func stop() {
        hotkeys.unregister()
    }

    private func handleSelectionHotkey(intent: WriteIntent) {
        Task { @MainActor in
            do {
                let text = try await selection.captureSelection()
                openPopup(with: text, intent: intent)
            } catch {
                openPopup(with: "", intent: intent, errorMessage: error.localizedDescription)
            }
        }
    }

    private func handleScreenshotOCR() {
        Task { @MainActor in
            // Permission gate. CGRequestScreenCaptureAccess() returns immediately and
            // triggers an async system prompt; if it says "not yet trusted" we route
            // the user to System Settings instead of running with no pixels.
            if !ScreenCaptureGuard.isTrusted {
                ScreenCaptureGuard.requestTrust()
                openPopup(
                    with: "",
                    intent: .dictionary,
                    errorMessage: String(localized: "Screen Recording permission required. Open System Settings → Privacy & Security → Screen Recording to enable Richer.")
                )
                return
            }

            guard let rect = await regionController.pickRegion() else {
                return // user cancelled
            }
            // Action-bar dismiss has its own click-outside monitor, so make sure no
            // stale bar lingers from a previous capture.
            actionBarController.dismiss()

            guard let image = ScreenshotCapture.capture(rect: rect) else {
                openPopup(
                    with: "",
                    intent: .dictionary,
                    errorMessage: String(localized: "Couldn't capture the selected region. Try again.")
                )
                return
            }

            do {
                let text = try await OCRService.recognize(image)
                actionBarController.show(text: text, nearRect: rect) { [weak self] action in
                    guard let self else { return }
                    switch action {
                    case .refine:
                        self.openPopup(with: text, intent: .refine)
                    case .translate:
                        self.openPopup(with: text, intent: .translate)
                    case .dictionary:
                        self.openPopup(with: text, intent: .dictionary)
                    case .copy:
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
            } catch {
                openPopup(with: "", intent: .dictionary, errorMessage: error.localizedDescription)
            }
        }
    }

    func openPopup(with text: String, intent: WriteIntent, errorMessage: String? = nil) {
        guard let modelContainer else {
            NSLog("[Richer] openPopup aborted: modelContainer not set")
            return
        }
        let viewModel = PopupViewModel(
            originalText: text,
            intent: intent,
            providerStore: providerStore,
            refineModeStore: refineModeStore,
            translateSettings: translateSettings
        )
        if let errorMessage {
            viewModel.errorMessage = errorMessage
        }
        popupController.show(viewModel: viewModel, at: NSEvent.mouseLocation, modelContainer: modelContainer)
    }

    func openInputWindow(intent: WriteIntent, prefilledText: String? = nil) {
        NSLog("[Richer] openInputWindow intent=\(intent)")
        guard let modelContainer else {
            NSLog("[Richer] openInputWindow aborted: modelContainer not set")
            return
        }
        if inputController.hasActiveSession {
            if let prefilledText, !prefilledText.isEmpty {
                inputController.appendToInput(prefilledText)
            }
            // The existing controller will reuse its panel + viewModel when we call show();
            // the parameter is ignored in the reuse path. Still, satisfy the API.
            let viewModel = inputController.viewModel ?? InputViewModel(
                providerStore: providerStore,
                refineModeStore: refineModeStore,
                translateSettings: translateSettings,
                actionCardStore: actionCardStore
            )
            inputController.show(
                viewModel: viewModel,
                modelContainer: modelContainer,
                onOpenHistory: { [weak self] in self?.openHistoryWindow() }
            )
            return
        }
        let viewModel = InputViewModel(
            providerStore: providerStore,
            refineModeStore: refineModeStore,
            translateSettings: translateSettings,
            actionCardStore: actionCardStore
        )
        if let prefilledText, !prefilledText.isEmpty {
            viewModel.inputText = prefilledText
        }
        inputController.show(
            viewModel: viewModel,
            modelContainer: modelContainer,
            onOpenHistory: { [weak self] in self?.openHistoryWindow() }
        )
    }

    func openCaptionBar() {
        captionController.show(coordinator: self)
    }

    func openHistoryWindow() {
        NSLog("[Richer] openHistoryWindow called")
        guard let modelContainer else {
            NSLog("[Richer] openHistoryWindow aborted: modelContainer not set")
            return
        }
        HistoryWindowController.shared.show(coordinator: self, modelContainer: modelContainer)
    }

    func rerun(entry: HistoryEntry) {
        switch entry.kind {
        case .refine:
            openPopup(with: entry.originalText, intent: .refine)
        case .translate:
            openPopup(with: entry.originalText, intent: .translate)
        case .dictionary:
            openPopup(with: entry.originalText, intent: .dictionary)
        }
    }
}

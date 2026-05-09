import AppKit
import Observation
import SwiftData

enum WriteIntent: Sendable, Equatable {
    case refine
    case translate
}

@Observable
@MainActor
final class Coordinator {
    private let popupController = PopupWindowController()
    private let inputController = InputWindowController()
    private let hotkeys = HotkeyManager()
    private let selection = SelectionCapture()
    let providerStore = ProviderStore()
    let refineModeStore = RefineModeStore()
    let translateSettings = TranslateSettings()
    let actionCardStore = ActionCardStore()
    var modelContainer: ModelContainer?

    func start() {
        hotkeys.register(
            onSelectionRefine: { [weak self] in self?.handleSelectionHotkey(intent: .refine) },
            onSelectionTranslate: { [weak self] in self?.handleSelectionHotkey(intent: .translate) },
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

    func openInputWindow(intent: WriteIntent) {
        NSLog("[Richer] openInputWindow intent=\(intent)")
        guard let modelContainer else {
            NSLog("[Richer] openInputWindow aborted: modelContainer not set")
            return
        }
        let viewModel = InputViewModel(
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
        }
    }
}

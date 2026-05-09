import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class PopupViewModel {
    let originalText: String
    var intent: WriteIntent
    var selectedRefineMode: RefineMode = .grammar
    var resultText: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?
    var providerLabelInUse: String = ""
    var resolvedTargetLanguage: String?
    var targetOverride: String?    // nil = auto

    private let providerStore: ProviderStore
    private let refineModeStore: RefineModeStore
    private let translateSettings: TranslateSettings
    private var streamTask: Task<Void, Never>?

    init(
        originalText: String,
        intent: WriteIntent,
        providerStore: ProviderStore,
        refineModeStore: RefineModeStore,
        translateSettings: TranslateSettings
    ) {
        self.originalText = originalText
        self.intent = intent
        self.providerStore = providerStore
        self.refineModeStore = refineModeStore
        self.translateSettings = translateSettings
    }

    func runIfNeeded(modelContext: ModelContext) {
        guard !originalText.isEmpty, !isStreaming, resultText.isEmpty else { return }
        run(modelContext: modelContext)
    }

    func run(modelContext: ModelContext) {
        cancel()
        resultText = ""
        errorMessage = nil
        isStreaming = true

        let captured = (originalText, intent, selectedRefineMode)
        streamTask = Task { @MainActor in
            do {
                guard let provider = providerStore.activeProvider else {
                    throw LLMError.noActiveProvider
                }
                self.providerLabelInUse = provider.label
                switch captured.1 {
                case .refine:
                    let service = RefineService(providerStore: providerStore, modeStore: refineModeStore)
                    let stream = try service.stream(text: captured.0, mode: captured.2, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        self.resultText += delta.text
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext,
                            kind: .refine,
                            original: captured.0,
                            result: self.resultText,
                            modeOrTargetLang: captured.2.rawValue,
                            provider: provider
                        )
                    }
                case .translate:
                    let service = TranslateService(providerStore: providerStore, settings: translateSettings)
                    let (stream, target) = try service.stream(text: captured.0, provider: provider, targetOverride: self.targetOverride)
                    self.resolvedTargetLanguage = target
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        self.resultText += delta.text
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext,
                            kind: .translate,
                            original: captured.0,
                            result: self.resultText,
                            modeOrTargetLang: target,
                            provider: provider
                        )
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func selectMode(_ mode: RefineMode, modelContext: ModelContext) {
        selectedRefineMode = mode
        run(modelContext: modelContext)
    }

    func switchTo(_ intent: WriteIntent, modelContext: ModelContext) {
        self.intent = intent
        run(modelContext: modelContext)
    }

    func selectTarget(_ code: String?, modelContext: ModelContext) {
        targetOverride = code
        if intent == .translate { run(modelContext: modelContext) }
    }
}

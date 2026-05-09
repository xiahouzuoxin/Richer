import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class PopupViewModel {
    let originalText: String
    var intent: WriteIntent
    var selectedRefineMode: RefineMode = .grammar
    var result: ActionResult = .empty
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

    var resultText: String { result.asText }

    /// True when the active provider for the dictionary intent has wordbook write capability.
    var providerCanWriteWordbook: Bool {
        guard intent == .dictionary,
              let provider = activeDictionaryProvider,
              let client = try? providerStore.makeDictionaryClient(for: provider)
        else { return false }
        return client.canWriteWordbook
    }

    private var activeDictionaryProvider: ProviderConfig? {
        providerStore.providers.first { $0.kind.isDictionaryKind }
    }

    func runIfNeeded(modelContext: ModelContext) {
        guard !originalText.isEmpty, !isStreaming, result.isEmpty else { return }
        run(modelContext: modelContext)
    }

    func run(modelContext: ModelContext) {
        cancel()
        result = .empty
        errorMessage = nil
        isStreaming = true

        let captured = (originalText, intent, selectedRefineMode)
        streamTask = Task { @MainActor in
            do {
                switch captured.1 {
                case .refine:
                    guard let provider = providerStore.activeProvider, provider.kind.isLLMKind else {
                        throw LLMError.noActiveProvider
                    }
                    self.providerLabelInUse = provider.label
                    self.result = .streamingText("")
                    let service = RefineService(providerStore: providerStore, modeStore: refineModeStore)
                    let stream = try service.stream(text: captured.0, mode: captured.2, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        self.result = .streamingText(self.result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext,
                            kind: .refine,
                            original: captured.0,
                            result: self.result.streamingText,
                            modeOrTargetLang: captured.2.rawValue,
                            provider: provider
                        )
                    }
                case .translate:
                    guard let provider = providerStore.activeProvider, provider.kind.isLLMKind else {
                        throw LLMError.noActiveProvider
                    }
                    self.providerLabelInUse = provider.label
                    self.result = .streamingText("")
                    let service = TranslateService(providerStore: providerStore, settings: translateSettings)
                    let (stream, target) = try service.stream(text: captured.0, provider: provider, targetOverride: self.targetOverride)
                    self.resolvedTargetLanguage = target
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        self.result = .streamingText(self.result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext,
                            kind: .translate,
                            original: captured.0,
                            result: self.result.streamingText,
                            modeOrTargetLang: target,
                            provider: provider
                        )
                    }
                case .dictionary:
                    guard let provider = activeDictionaryProvider else {
                        throw LLMError.noActiveProvider
                    }
                    self.providerLabelInUse = provider.label
                    let service = DictionaryService(providerStore: providerStore)
                    let entry = try await service.lookup(text: captured.0, provider: provider)
                    if !Task.isCancelled {
                        self.result = .dictionary(entry)
                        HistoryWriter.record(
                            in: modelContext,
                            kind: .dictionary,
                            original: entry.word,
                            result: entry.plainTextSummary,
                            modeOrTargetLang: entry.sourceLabel,
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

    func addToWordbook() async throws {
        guard case .dictionary(let entry) = result else { return }
        guard let provider = activeDictionaryProvider else { throw LLMError.noActiveProvider }
        let service = DictionaryService(providerStore: providerStore)
        try await service.addToWordbook(word: entry.word, provider: provider)
    }
}

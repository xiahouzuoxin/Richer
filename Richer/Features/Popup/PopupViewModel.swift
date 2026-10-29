import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class PopupViewModel {
    let originalText: String
    var intent: WriteIntent
    var refineOptions: RefineOptions = .polish
    var replyContext = ""
    var result: ActionResult = .empty
    var isStreaming: Bool = false
    var errorMessage: String?
    var providerLabelInUse: String = ""
    var resolvedTargetLanguage: String?
    var targetOverride: String?    // nil = auto
    var sourceOverride: String?    // nil = auto-detect

    private let providerStore: ProviderStore
    private let refinePromptStore: RefinePromptStore
    private let translateSettings: TranslateSettings
    private let replySettings: ReplySettings
    private var streamTask: Task<Void, Never>?

    init(
        originalText: String,
        intent: WriteIntent,
        providerStore: ProviderStore,
        refinePromptStore: RefinePromptStore,
        translateSettings: TranslateSettings,
        replySettings: ReplySettings
    ) {
        self.originalText = originalText
        self.intent = intent
        self.providerStore = providerStore
        self.refinePromptStore = refinePromptStore
        self.translateSettings = translateSettings
        self.replySettings = replySettings
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

        let captured = (originalText, intent, refineOptions)
        let capturedReplyContext = replyContext
        streamTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            do {
                switch captured.1 {
                case .refine:
                    guard let provider = providerStore.activeProvider, provider.kind.isLLMKind else {
                        throw LLMError.noActiveProvider
                    }
                    self.providerLabelInUse = provider.label
                    self.result = .streamingText("")
                    let service = RefineService(providerStore: providerStore, promptStore: refinePromptStore)
                    let stream = try service.stream(text: captured.0, options: captured.2, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { return }
                        self.result = .streamingText(self.result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext,
                            kind: .refine,
                            original: captured.0,
                            result: self.result.streamingText,
                            modeOrTargetLang: "polish",
                            provider: provider, refineOptions: captured.2
                        )
                    }
                case .translate:
                    guard let provider = providerStore.activeProvider, provider.kind.isLLMKind else {
                        throw LLMError.noActiveProvider
                    }
                    self.providerLabelInUse = provider.label
                    self.result = .streamingText("")
                    let service = TranslateService(providerStore: providerStore, settings: translateSettings)
                    let (stream, target) = try service.stream(text: captured.0, provider: provider, targetOverride: self.targetOverride, sourceOverride: self.sourceOverride)
                    self.resolvedTargetLanguage = target
                    for try await delta in stream {
                        if Task.isCancelled { return }
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
                case .reply:
                    guard let provider = providerStore.activeProvider, provider.kind.isLLMKind else {
                        throw LLMError.noActiveProvider
                    }
                    self.providerLabelInUse = provider.label
                    self.result = .streamingText("")
                    let stream = try ReplyService(providerStore: providerStore, settings: replySettings).stream(
                        message: captured.0, context: capturedReplyContext, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { return }
                        self.result = .streamingText(self.result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(in: modelContext, kind: .reply, original: captured.0,
                            result: self.result.streamingText, modeOrTargetLang: "reply", provider: provider,
                            replyContext: capturedReplyContext)
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
            guard !Task.isCancelled else { return }
            self.isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func selectOptions(_ options: RefineOptions, modelContext: ModelContext) {
        refineOptions = options
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

    func selectSource(_ code: String?, modelContext: ModelContext) {
        sourceOverride = code
        if intent == .translate { run(modelContext: modelContext) }
    }

    func addToWordbook() async throws {
        guard case .dictionary(let entry) = result else { return }
        guard let provider = activeDictionaryProvider else { throw LLMError.noActiveProvider }
        let service = DictionaryService(providerStore: providerStore)
        try await service.addToWordbook(word: entry.word, provider: provider)
    }
}

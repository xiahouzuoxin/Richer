import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CardViewModel {
    let card: ActionCard
    var refineOptions: RefineOptions = .polish
    var replyContext = ""
    var isExpanded: Bool = false
    var result: ActionResult = .empty
    var isStreaming: Bool = false
    var errorMessage: String?
    var providerLabel: String = ""
    var resolvedTargetLanguage: String?
    /// Hash of the input that produced the current `result`. Used to detect staleness.
    var lastRunInputHash: Int?

    var resultText: String { result.asText }

    private let providerStore: ProviderStore
    private let refinePromptStore: RefinePromptStore
    private let translateSettings: TranslateSettings
    private let replySettings: ReplySettings
    private var streamTask: Task<Void, Never>?

    init(
        card: ActionCard,
        providerStore: ProviderStore,
        refinePromptStore: RefinePromptStore,
        translateSettings: TranslateSettings,
        replySettings: ReplySettings
    ) {
        self.card = card
        if case .refine(let options) = card.action { self.refineOptions = options }
        self.providerStore = providerStore
        self.refinePromptStore = refinePromptStore
        self.translateSettings = translateSettings
        self.replySettings = replySettings
    }

    var headerLabel: String {
        let providerLabelResolved = providerStore.providers.first { $0.id == card.providerID }?.label ?? String(localized: "Unknown")
        return "\(refineLabel) · \(providerLabelResolved)"
    }

    var actionSymbol: String {
        if case .refine = card.action { return refineOptions.symbol }
        return card.action.symbol
    }

    private var refineLabel: String {
        if case .refine = card.action { return refineOptions.label }
        return card.action.label
    }

    var isProviderMissing: Bool {
        providerStore.providers.first { $0.id == card.providerID } == nil
    }

    /// True only when the card's action is .dictionary AND the provider has credentials
    /// that allow writing to the user's wordbook (Eudic with a saved token).
    var providerCanWriteWordbook: Bool {
        guard case .dictionary = card.action,
              let provider = providerStore.providers.first(where: { $0.id == card.providerID }),
              let client = try? providerStore.makeDictionaryClient(for: provider)
        else { return false }
        return client.canWriteWordbook
    }

    /// Click handler. Only changes the visual expansion state; never cancels in-flight work.
    /// When expanding, runs the action only if the result is empty/stale and not already streaming.
    func toggle(input: String, targetOverride: String?, sourceOverride: String? = nil, modelContext: ModelContext) {
        if isExpanded {
            isExpanded = false
            return
        }
        isExpanded = true
        let trimmedHash = input.trimmingCharacters(in: .whitespacesAndNewlines).hashValue
        let needsRun = !isStreaming && (result.isEmpty || lastRunInputHash != trimmedHash)
        if needsRun {
            run(input: input, targetOverride: targetOverride, sourceOverride: sourceOverride, modelContext: modelContext)
        }
    }

    /// Visual collapse without affecting in-flight work or stored results.
    func collapse() {
        isExpanded = false
    }

    func run(input: String, targetOverride: String?, sourceOverride: String? = nil, modelContext: ModelContext) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "Type something to refine, translate, or reply to.")
            return
        }
        cancel()
        result = .empty
        errorMessage = nil
        isStreaming = true
        lastRunInputHash = trimmed.hashValue

        let capturedOptions = refineOptions
        let capturedReplyContext = replyContext
        streamTask = Task { @MainActor [self] in
            guard !Task.isCancelled else { return }
            do {
                guard let provider = providerStore.providers.first(where: { $0.id == card.providerID }) else {
                    throw LLMError.noActiveProvider
                }
                providerLabel = provider.label

                switch card.action {
                case .refine:
                    result = .streamingText("")
                    let service = RefineService(providerStore: providerStore, promptStore: refinePromptStore)
                    let stream = try service.stream(text: trimmed, options: capturedOptions, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { return }
                        result = .streamingText(result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext, kind: .refine,
                            original: trimmed, result: result.streamingText,
                            modeOrTargetLang: "polish", provider: provider, refineOptions: capturedOptions
                        )
                    }
                case .translate:
                    result = .streamingText("")
                    let service = TranslateService(providerStore: providerStore, settings: translateSettings)
                    let (stream, target) = try service.stream(text: trimmed, provider: provider, targetOverride: targetOverride, sourceOverride: sourceOverride)
                    resolvedTargetLanguage = target
                    for try await delta in stream {
                        if Task.isCancelled { return }
                        result = .streamingText(result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext, kind: .translate,
                            original: trimmed, result: result.streamingText,
                            modeOrTargetLang: target, provider: provider
                        )
                    }
                case .reply:
                    result = .streamingText("")
                    let stream = try ReplyService(providerStore: providerStore, settings: replySettings).stream(
                        message: trimmed, context: capturedReplyContext, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { return }
                        result = .streamingText(result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(in: modelContext, kind: .reply, original: trimmed,
                            result: result.streamingText, modeOrTargetLang: "reply", provider: provider,
                            replyContext: capturedReplyContext)
                    }
                case .dictionary:
                    let service = DictionaryService(providerStore: providerStore)
                    let entry = try await service.lookup(text: trimmed, provider: provider)
                    if !Task.isCancelled {
                        result = .dictionary(entry)
                        HistoryWriter.record(
                            in: modelContext, kind: .dictionary,
                            original: entry.word, result: entry.plainTextSummary,
                            modeOrTargetLang: entry.sourceLabel, provider: provider
                        )
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            guard !Task.isCancelled else { return }
            isStreaming = false
        }
    }

    /// Add the current dictionary result's word to the provider's wordbook (Eudic only).
    /// Throws DictionaryError.missingAuth if no token is configured.
    func addToWordbook() async throws {
        guard case .dictionary(let entry) = result else { return }
        guard let provider = providerStore.providers.first(where: { $0.id == card.providerID }) else {
            throw LLMError.noActiveProvider
        }
        let service = DictionaryService(providerStore: providerStore)
        try await service.addToWordbook(word: entry.word, provider: provider)
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func reset() {
        cancel()
        result = .empty
        errorMessage = nil
        resolvedTargetLanguage = nil
        lastRunInputHash = nil
    }
}

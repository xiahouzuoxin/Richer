import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CardViewModel {
    let card: ActionCard
    var isExpanded: Bool = false
    var result: ActionResult = .empty
    var isStreaming: Bool = false
    var errorMessage: String?
    var providerLabel: String = ""
    var resolvedTargetLanguage: String?
    /// Hash of the input that produced the current `result`. Used to detect staleness.
    var lastRunInputHash: Int?

    /// Convenience for tests / clients that only consume streamed text.
    var resultText: String { result.asText }

    private let providerStore: ProviderStore
    private let refineModeStore: RefineModeStore
    private let translateSettings: TranslateSettings
    private var streamTask: Task<Void, Never>?

    init(
        card: ActionCard,
        providerStore: ProviderStore,
        refineModeStore: RefineModeStore,
        translateSettings: TranslateSettings
    ) {
        self.card = card
        self.providerStore = providerStore
        self.refineModeStore = refineModeStore
        self.translateSettings = translateSettings
    }

    var headerLabel: String {
        let providerLabelResolved = providerStore.providers.first { $0.id == card.providerID }?.label ?? String(localized: "Unknown")
        return "\(card.action.label) · \(providerLabelResolved)"
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
            errorMessage = "Type something to refine or translate."
            return
        }
        cancel()
        result = .empty
        errorMessage = nil
        isStreaming = true
        lastRunInputHash = trimmed.hashValue

        streamTask = Task { @MainActor [self] in
            do {
                guard let provider = providerStore.providers.first(where: { $0.id == card.providerID }) else {
                    throw LLMError.noActiveProvider
                }
                providerLabel = provider.label

                switch card.action {
                case .refine(let mode):
                    result = .streamingText("")
                    let service = RefineService(providerStore: providerStore, modeStore: refineModeStore)
                    let stream = try service.stream(text: trimmed, mode: mode, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        result = .streamingText(result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext, kind: .refine,
                            original: trimmed, result: result.streamingText,
                            modeOrTargetLang: mode.rawValue, provider: provider
                        )
                    }
                case .translate:
                    result = .streamingText("")
                    let service = TranslateService(providerStore: providerStore, settings: translateSettings)
                    let (stream, target) = try service.stream(text: trimmed, provider: provider, targetOverride: targetOverride, sourceOverride: sourceOverride)
                    resolvedTargetLanguage = target
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        result = .streamingText(result.streamingText + delta.text)
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext, kind: .translate,
                            original: trimmed, result: result.streamingText,
                            modeOrTargetLang: target, provider: provider
                        )
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

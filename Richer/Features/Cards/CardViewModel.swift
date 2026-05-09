import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class CardViewModel {
    let card: ActionCard
    var isExpanded: Bool = false
    var resultText: String = ""
    var isStreaming: Bool = false
    var errorMessage: String?
    var providerLabel: String = ""
    var resolvedTargetLanguage: String?
    /// Hash of the input that produced the current `resultText`. Used to detect staleness.
    var lastRunInputHash: Int?

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

    /// Click handler. Only changes the visual expansion state; never cancels in-flight work.
    /// When expanding, runs the action only if the result is empty/stale and not already streaming.
    func toggle(input: String, targetOverride: String?, modelContext: ModelContext) {
        if isExpanded {
            isExpanded = false
            return
        }
        isExpanded = true
        let trimmedHash = input.trimmingCharacters(in: .whitespacesAndNewlines).hashValue
        let needsRun = !isStreaming && (resultText.isEmpty || lastRunInputHash != trimmedHash)
        if needsRun {
            run(input: input, targetOverride: targetOverride, modelContext: modelContext)
        }
    }

    /// Visual collapse without affecting in-flight work or stored results.
    func collapse() {
        isExpanded = false
    }

    func run(input: String, targetOverride: String?, modelContext: ModelContext) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Type something to refine or translate."
            return
        }
        cancel()
        resultText = ""
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
                    let service = RefineService(providerStore: providerStore, modeStore: refineModeStore)
                    let stream = try service.stream(text: trimmed, mode: mode, provider: provider)
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        resultText += delta.text
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext, kind: .refine,
                            original: trimmed, result: resultText,
                            modeOrTargetLang: mode.rawValue, provider: provider
                        )
                    }
                case .translate:
                    let service = TranslateService(providerStore: providerStore, settings: translateSettings)
                    let (stream, target) = try service.stream(text: trimmed, provider: provider, targetOverride: targetOverride)
                    resolvedTargetLanguage = target
                    for try await delta in stream {
                        if Task.isCancelled { break }
                        resultText += delta.text
                    }
                    if !Task.isCancelled {
                        HistoryWriter.record(
                            in: modelContext, kind: .translate,
                            original: trimmed, result: resultText,
                            modeOrTargetLang: target, provider: provider
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

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func reset() {
        cancel()
        resultText = ""
        errorMessage = nil
        resolvedTargetLanguage = nil
        lastRunInputHash = nil
    }
}

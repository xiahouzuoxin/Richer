import Foundation
import SwiftData

@MainActor
enum HistoryWriter {
    static func record(
        in context: ModelContext,
        kind: HistoryKind,
        original: String,
        result: String,
        modeOrTargetLang: String,
        provider: ProviderConfig,
        refineOptions: RefineOptions? = nil,
        replyContext: String? = nil
    ) {
        let entry = HistoryEntry(
            kind: kind,
            originalText: original,
            resultText: result,
            modeOrTargetLang: modeOrTargetLang,
            providerLabel: provider.label,
            modelID: provider.defaultModel
        )
        if let refineOptions {
            entry.refineOptionsData = try? JSONEncoder().encode(refineOptions)
        }
        entry.replyContext = replyContext
        context.insert(entry)
        try? context.save()
    }
}

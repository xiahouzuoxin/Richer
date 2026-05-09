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
        provider: ProviderConfig
    ) {
        let entry = HistoryEntry(
            kind: kind,
            originalText: original,
            resultText: result,
            modeOrTargetLang: modeOrTargetLang,
            providerLabel: provider.label,
            modelID: provider.defaultModel
        )
        context.insert(entry)
        try? context.save()
    }
}

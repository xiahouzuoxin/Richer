import Foundation
import SwiftData

enum HistoryKind: String, Codable {
    case refine
    case translate
}

@Model
final class HistoryEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var kindRaw: String
    var originalText: String
    var resultText: String
    /// For refine: RefineMode.rawValue. For translate: ISO language code.
    var modeOrTargetLang: String
    var providerLabel: String
    var modelID: String

    var kind: HistoryKind {
        get { HistoryKind(rawValue: kindRaw) ?? .refine }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        kind: HistoryKind,
        originalText: String,
        resultText: String,
        modeOrTargetLang: String,
        providerLabel: String,
        modelID: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kindRaw = kind.rawValue
        self.originalText = originalText
        self.resultText = resultText
        self.modeOrTargetLang = modeOrTargetLang
        self.providerLabel = providerLabel
        self.modelID = modelID
    }
}

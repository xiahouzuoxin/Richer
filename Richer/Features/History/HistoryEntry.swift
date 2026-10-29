import Foundation
import SwiftData

enum HistoryKind: String, Codable {
    case refine
    case translate
    case reply
    case dictionary
}

@Model
final class HistoryEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var kindRaw: String
    var originalText: String
    var resultText: String
    /// Refine operation identifier; translate uses an ISO language code.
    var modeOrTargetLang: String
    var providerLabel: String
    var modelID: String
    var refineOptionsData: Data?
    var replyContext: String?

    var refineOptions: RefineOptions {
        if let data = refineOptionsData,
           let options = try? JSONDecoder().decode(RefineOptions.self, from: data) { return options }
        return RefineOptions(storedMode: modeOrTargetLang)
    }

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

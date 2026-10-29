// v1 on-disk schema fixture. Keep unchanged to exercise lightweight migration.
import Foundation
import SwiftData

@Model final class HistoryEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var kindRaw: String
    var originalText: String
    var resultText: String
    var modeOrTargetLang: String
    var providerLabel: String
    var modelID: String

    init() {
        id = UUID()
        timestamp = .now
        kindRaw = "refine"
        originalText = "Legacy input"
        resultText = "Legacy result"
        modeOrTargetLang = "professional"
        providerLabel = "Offline"
        modelID = "test"
    }
}

@main struct SeedLegacyHistory {
    @MainActor static func main() throws {
        let configuration = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let container = try ModelContainer(for: HistoryEntry.self, configurations: configuration)
        container.mainContext.insert(HistoryEntry())
        try container.mainContext.save()
    }
}

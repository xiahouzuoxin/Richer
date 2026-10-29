import Foundation
import SwiftData

// Minimal unrelated provider definitions keep these regression tests offline.
enum ProviderKind { case llm, dictionary
    var isLLMKind: Bool { self == .llm }
    var isDictionaryKind: Bool { self == .dictionary }
}
struct ProviderConfig { let label: String; let defaultModel: String }

@main struct RefineTests {
    @MainActor static func main() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let suite = "richer.refine.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RefinePromptStore(defaults: defaults)

        // Decode the actual synthesized v1 associated-value shape, not a new-model fixture.
        for mode in ["grammar", "polish", "professional", "concise", "casual"] {
            let json = "{\"refine\":{\"_0\":\"\(mode)\"}}"
            let action = try decoder.decode(ActionKind.self, from: Data(json.utf8))
            guard case .refine(let options) = action else { fatalError("Wrong action") }
            precondition(options == RefineOptions(storedMode: mode))
            let roundTrip = try decoder.decode(ActionKind.self, from: encoder.encode(action))
            precondition(roundTrip == action)
        }
        let cardJSON = """
        {"id":"00000000-0000-0000-0000-000000000001","providerID":"00000000-0000-0000-0000-000000000002","action":{"refine":{"_0":"professional"}},"enabled":false}
        """
        let card = try decoder.decode(ActionCard.self, from: Data(cardJSON.utf8))
        precondition(!card.enabled && card.action.label.contains(RefineTone.professional.label))
        for tone in RefineTone.allCases {
            for length in RefineLength.allCases {
                let options = RefineOptions(tone: tone, length: length)
                let prompt = store.template(for: options)
                let messages = prompt.messages(for: "Original input 42")
                precondition(messages.count == 2 && messages[1].content.contains("Original input 42"))
                precondition(prompt.system.contains("same language") && prompt.system.contains("Do not invent"))
                precondition(prompt.system.contains("Correct grammar, spelling, and punctuation errors"))
                if tone == .professional { precondition(prompt.system.contains(DefaultPrompts.refineInstruction(for: .professional))) }
                if tone == .casual { precondition(prompt.system.contains(DefaultPrompts.refineInstruction(for: .casual))) }
                if length == .concise { precondition(prompt.system.contains(DefaultPrompts.refineInstruction(for: .concise))) }
                if length == .expand { precondition(prompt.system.contains(DefaultPrompts.refineInstruction(for: .expand))) }
                let roundTrip = try decoder.decode(RefineOptions.self, from: encoder.encode(options))
                precondition(roundTrip == options)
            }
        }
        precondition(store.template(for: RefineOptions(storedMode: "grammar")).system == store.template(for: .polish).system)
        store.setInstruction("Custom concise instruction", for: .concise)
        let reloaded = RefinePromptStore(defaults: defaults)
        precondition(reloaded.template(for: RefineOptions(length: .concise)).system.contains("Custom concise instruction"))
        reloaded.setInstruction(nil, for: .concise)
        precondition(reloaded.instruction(for: .concise) == DefaultPrompts.refineInstruction(for: .concise))

        let container = try ModelContainer(for: HistoryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let options = RefineOptions(tone: .professional, length: .concise)
        HistoryWriter.record(in: context, kind: .refine, original: "Original", result: "Result",
                             modeOrTargetLang: "polish", provider: ProviderConfig(label: "Offline", defaultModel: "test"), refineOptions: options)
        let saved = try context.fetch(FetchDescriptor<HistoryEntry>())
        precondition(saved.count == 1 && saved[0].refineOptions == options)
        HistoryWriter.record(in: context, kind: .reply, original: "Are you free?", result: "What time?",
                             modeOrTargetLang: "reply", provider: ProviderConfig(label: "Offline", defaultModel: "test"),
                             replyContext: "Ask what time")
        let replies = try context.fetch(FetchDescriptor<HistoryEntry>()).filter { $0.kind == .reply }
        precondition(replies.count == 1 && replies[0].replyContext == "Ask what time")
        let replyCard = ActionCard(providerID: UUID(), action: .reply)
        let decodedReply = try decoder.decode(ActionCard.self, from: encoder.encode(replyCard))
        precondition(decodedReply == replyCard && decodedReply.action.historyKind == .reply)
        precondition(decodedReply.action.compatibleProviderKinds(.llm) && !decodedReply.action.compatibleProviderKinds(.dictionary))
        let legacy = HistoryEntry(kind: .refine, originalText: "Old", resultText: "Old result",
                                  modeOrTargetLang: "casual", providerLabel: "Offline", modelID: "test")
        precondition(legacy.refineOptions == RefineOptions(tone: .casual))
        if CommandLine.arguments.count > 1 {
            let configuration = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
            let diskContainer = try ModelContainer(for: HistoryEntry.self, configurations: configuration)
            let entries = try diskContainer.mainContext.fetch(FetchDescriptor<HistoryEntry>())
            precondition(entries.count == 1 && entries[0].originalText == "Legacy input")
            precondition(entries[0].refineOptions == RefineOptions(tone: .professional))
            entries[0].refineOptionsData = try encoder.encode(options)
            try diskContainer.mainContext.save()
            let reopened = try ModelContainer(for: HistoryEntry.self, configurations: configuration)
            let migratedEntries = try reopened.mainContext.fetch(FetchDescriptor<HistoryEntry>())
            precondition(migratedEntries[0].refineOptions == options)
            print("PASS: v1 SwiftData store migrated, original history retained, new options saved and reopened")
        }
        print("PASS: legacy modes, disabled card, 9 option combinations including expansion with mandatory grammar correction, instruction persistence, structured and legacy history, reply cards and reply history")
    }
}

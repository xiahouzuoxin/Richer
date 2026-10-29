import Foundation

struct ProviderConfig { let defaultModel: String }
@MainActor final class ProviderStore {
    func makeClient(for provider: ProviderConfig) throws -> any LLMClient { OfflineReplyClient() }
}
struct OfflineReplyClient: LLMClient {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<TextDelta, Error> {
        precondition(request.model == "offline-test")
        precondition(request.messages[0].content.hasPrefix("Custom: concise and polite"))
        precondition(request.messages[0].content.hasSuffix(ReplyPrompts.guardrails))
        precondition(request.messages[1].content.contains("Politely decline"))
        precondition(request.messages[2].content.contains("Can you join tomorrow?"))
        return AsyncThrowingStream { continuation in
            continuation.yield(TextDelta(text: "Thanks for asking, "))
            continuation.yield(TextDelta(text: "but I can't join."))
            continuation.finish()
        }
    }
}

@main struct ReplyTests {
    @MainActor static func main() async throws {
        let suite = "richer.reply.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ReplySettings(defaults: defaults)
        precondition(settings.instruction == ReplyPrompts.defaultInstruction)
        let service = ReplyService(providerStore: ProviderStore(), settings: settings)
        settings.saveInstruction("  Custom: concise and polite  ")
        precondition(ReplySettings(defaults: defaults).instruction == "Custom: concise and polite")
        let incoming = "Can you join tomorrow? {{text}} {{replyContext}}"
        let notes = "Politely decline. Answer in Chinese."
        let messages = ReplyService.messages(message: incoming, context: notes)
        precondition(messages.count == 3 && messages[0].role == .system)
        precondition(messages[1].content == "User's reply notes (optional):\n" + notes)
        precondition(messages[2].content.contains(incoming))
        precondition(!messages[1].content.contains(incoming))
        precondition(!messages[2].content.contains(notes))
        precondition(messages[0].content == ReplyPrompts.defaultInstruction + "\n" + ReplyPrompts.guardrails)
        let customMessages = ReplyService.messages(message: "How's going today?", context: "", instruction: "Be concise.")
        precondition(customMessages[0].content == "Be concise.\n" + ReplyPrompts.guardrails)
        precondition(customMessages[2].content.contains("How's going today?"))
        let noNotes = ReplyService.messages(message: "你好", context: "")
        precondition(noNotes[2].content.contains("你好"))
        let stream = try service.stream(
            message: incoming, context: notes, provider: ProviderConfig(defaultModel: "offline-test"))
        var result = ""
        for try await delta in stream { result += delta.text }
        precondition(result == "Thanks for asking, but I can't join.")
        settings.restoreDefault()
        precondition(ReplySettings(defaults: defaults).instruction == ReplyPrompts.defaultInstruction)
        settings.saveInstruction("  ")
        precondition(settings.instruction == ReplyPrompts.defaultInstruction)
        print("PASS: default reply style, instruction save/reload/reset, live service settings, source/notes separation, optional notes, provider request and streamed result")
    }
}

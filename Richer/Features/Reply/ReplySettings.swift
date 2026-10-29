import Foundation
import Observation

enum ReplyPrompts {
    static let defaultInstruction = """
    Answer the sender's questions directly by a natural, authentic, concise, and accurate way, like a local resident would.
    """

    static let guardrails = """
    Answer the sender's questions rather than rewriting or summarizing their message. Use the incoming message's language unless the user requests another language. Output ONLY one ready-to-send reply.
    """
}

@Observable
@MainActor
final class ReplySettings {
    private(set) var instruction: String
    private let defaults: UserDefaults
    private let storageKey = "richer.replyInstruction.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        instruction = defaults.string(forKey: storageKey) ?? ReplyPrompts.defaultInstruction
    }

    func saveInstruction(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { restoreDefault(); return }
        instruction = trimmed
        defaults.set(trimmed, forKey: storageKey)
    }

    func restoreDefault() {
        defaults.removeObject(forKey: storageKey)
        instruction = ReplyPrompts.defaultInstruction
    }
}

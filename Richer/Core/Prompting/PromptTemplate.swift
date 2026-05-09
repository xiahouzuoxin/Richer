import Foundation

struct PromptTemplate: Sendable {
    let system: String
    let userTemplate: String

    func messages(for text: String, additionalContext: [String: String] = [:]) -> [ChatMessage] {
        var rendered = userTemplate.replacingOccurrences(of: "{{text}}", with: text)
        for (key, value) in additionalContext {
            rendered = rendered.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return [
            ChatMessage(role: .system, content: system),
            ChatMessage(role: .user, content: rendered)
        ]
    }
}

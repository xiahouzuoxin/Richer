import Foundation
import SwiftUI

@MainActor
struct ReplyService {
    let providerStore: ProviderStore
    let settings: ReplySettings

    static func messages(message: String, context: String, instruction: String = ReplyPrompts.defaultInstruction) -> [ChatMessage] {
        [
            ChatMessage(role: .system, content: instruction + "\n" + ReplyPrompts.guardrails),
            ChatMessage(role: .user, content: "User's reply notes (optional):\n" + context),
            ChatMessage(role: .user, content: "Incoming message to reply to:\n<message>\n" + message + "\n</message>")
        ]
    }

    func stream(message: String, context: String, provider: ProviderConfig) throws -> AsyncThrowingStream<TextDelta, Error> {
        let client = try providerStore.makeClient(for: provider)
        return client.stream(LLMRequest(model: provider.defaultModel,
                                       messages: Self.messages(message: message, context: context, instruction: settings.instruction), temperature: 0.3))
    }
}

struct ReplyContextView: View {
    @Binding var context: String
    var onGenerate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Reply notes (optional)", text: $context)
                .textFieldStyle(.roundedBorder)
                .help("For example: politely decline, or say Friday works for me.")
                .onSubmit(onGenerate)
            Button("Generate reply", action: onGenerate)
        }
    }
}

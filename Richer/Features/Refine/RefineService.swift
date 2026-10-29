import Foundation

@MainActor
struct RefineService {
    let providerStore: ProviderStore
    let promptStore: RefinePromptStore

    func stream(text: String, options: RefineOptions, provider: ProviderConfig) throws -> AsyncThrowingStream<TextDelta, Error> {
        let client = try providerStore.makeClient(for: provider)
        let template = promptStore.template(for: options)
        let messages = template.messages(for: text)
        let request = LLMRequest(model: provider.defaultModel, messages: messages, temperature: 0.3)
        return client.stream(request)
    }
}

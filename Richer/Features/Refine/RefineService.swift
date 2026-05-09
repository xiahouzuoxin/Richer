import Foundation

@MainActor
struct RefineService {
    let providerStore: ProviderStore
    let modeStore: RefineModeStore

    func stream(text: String, mode: RefineMode, provider: ProviderConfig) throws -> AsyncThrowingStream<TextDelta, Error> {
        let client = try providerStore.makeClient(for: provider)
        let template = modeStore.template(for: mode)
        let messages = template.messages(for: text)
        let request = LLMRequest(model: provider.defaultModel, messages: messages, temperature: 0.3)
        return client.stream(request)
    }
}

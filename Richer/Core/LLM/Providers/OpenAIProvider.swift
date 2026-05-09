import Foundation

struct OpenAIProvider: LLMClient {
    let apiKey: String
    private let inner: OpenAICompatibleProvider

    init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
        self.apiKey = apiKey
        self.inner = OpenAICompatibleProvider(baseURL: baseURL, apiKey: apiKey)
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<TextDelta, Error> {
        inner.stream(request)
    }
}

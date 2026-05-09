import Foundation

struct ChatMessage: Sendable, Equatable {
    enum Role: String, Sendable { case system, user, assistant }
    let role: Role
    let content: String
}

struct LLMRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int?

    init(model: String, messages: [ChatMessage], temperature: Double = 0.3, maxTokens: Int? = 2048) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

struct TextDelta: Sendable, Equatable {
    let text: String
}

protocol LLMClient: Sendable {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<TextDelta, Error>
}

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case http(status: Int, body: String)
    case decoding(String)
    case noActiveProvider

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API key is missing for this provider."
        case .invalidEndpoint: "Provider endpoint URL is invalid."
        case .http(let status, let body): "HTTP \(status): \(body)"
        case .decoding(let msg): "Decoding error: \(msg)"
        case .noActiveProvider: "No active LLM provider is configured. Open Settings → Providers."
        }
    }
}

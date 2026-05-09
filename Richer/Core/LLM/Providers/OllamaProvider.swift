import Foundation

struct OllamaProvider: LLMClient {
    var baseURL: URL = URL(string: "http://127.0.0.1:11434")!
    private let streaming = StreamingClient()

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<TextDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlReq = try buildRequest(from: request)
                    let lines = streaming.bytes(for: urlReq, format: .ndjson)
                    for try await line in lines {
                        if Task.isCancelled { break }
                        guard case .raw(let json) = line else { continue }
                        guard let data = json.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(OllamaChatChunk.self, from: data) {
                            if let text = chunk.message?.content, !text.isEmpty {
                                continuation.yield(TextDelta(text: text))
                            }
                            if chunk.done == true { break }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildRequest(from req: LLMRequest) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent("api/chat")
        var urlReq = URLRequest(url: endpoint)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": req.model,
            "messages": req.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true,
            "options": ["temperature": req.temperature]
        ]
        urlReq.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return urlReq
    }
}

private struct OllamaChatChunk: Decodable {
    let message: Message?
    let done: Bool?
    struct Message: Decodable { let role: String?; let content: String? }
}

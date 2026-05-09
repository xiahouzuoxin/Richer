import Foundation

struct OpenAICompatibleProvider: LLMClient {
    let baseURL: URL
    let apiKey: String
    let streaming = StreamingClient()

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<TextDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlReq = try buildRequest(from: request)
                    let lines = streaming.bytes(for: urlReq, format: .sse)
                    for try await line in lines {
                        if Task.isCancelled { break }
                        guard case .data(let payload) = line else { continue }
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content,
                           !delta.isEmpty {
                            continuation.yield(TextDelta(text: delta))
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
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var urlReq = URLRequest(url: endpoint)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlReq.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "model": req.model,
            "messages": req.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": req.temperature,
            "stream": true,
            "max_tokens": req.maxTokens as Any
        ].compactMapValues { $0 is NSNull ? nil : $0 }

        urlReq.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return urlReq
    }
}

private struct ChatStreamChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: Delta
        struct Delta: Decodable { let content: String? }
    }
}

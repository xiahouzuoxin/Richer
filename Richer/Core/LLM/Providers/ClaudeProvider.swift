import Foundation

struct ClaudeProvider: LLMClient {
    let apiKey: String
    var baseURL: URL = URL(string: "https://api.anthropic.com/v1")!
    var apiVersion: String = "2023-06-01"
    private let streaming = StreamingClient()

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<TextDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlReq = try buildRequest(from: request)
                    let lines = streaming.bytes(for: urlReq, format: .sse)
                    var currentEvent: String = ""
                    for try await line in lines {
                        if Task.isCancelled { break }
                        switch line {
                        case .event(let name):
                            currentEvent = name
                        case .data(let payload):
                            if currentEvent == "content_block_delta" {
                                if let data = payload.data(using: .utf8),
                                   let evt = try? JSONDecoder().decode(ContentBlockDelta.self, from: data),
                                   let text = evt.delta.text, !text.isEmpty {
                                    continuation.yield(TextDelta(text: text))
                                }
                            } else if currentEvent == "message_stop" {
                                continuation.finish()
                                return
                            }
                        case .raw:
                            continue
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
        let endpoint = baseURL.appendingPathComponent("messages")
        var urlReq = URLRequest(url: endpoint)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlReq.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlReq.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let systemMessages = req.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let userAssistantMessages = req.messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        var body: [String: Any] = [
            "model": req.model,
            "messages": userAssistantMessages,
            "max_tokens": req.maxTokens ?? 2048,
            "stream": true
        ]
        // Newer Claude models (opus-4-7+) reject the `temperature` parameter outright.
        if !Self.modelRejectsTemperature(req.model) {
            body["temperature"] = req.temperature
        }
        if !systemMessages.isEmpty { body["system"] = systemMessages }

        urlReq.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return urlReq
    }

    private static func modelRejectsTemperature(_ model: String) -> Bool {
        let lower = model.lowercased()
        return lower.contains("opus-4-7")
    }
}

private struct ContentBlockDelta: Decodable {
    let type: String
    let delta: Delta
    struct Delta: Decodable { let type: String?; let text: String? }
}

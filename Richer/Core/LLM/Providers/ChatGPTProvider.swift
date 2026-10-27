import Foundation

struct ChatGPTProvider: LLMClient {
    let account: String

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<TextDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await ChatGPTAuth.shared.accessToken(account: account)
                    var http = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
                    http.httpMethod = "POST"
                    http.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let instructions = request.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
                    let input = request.messages.filter { $0.role != .system }.map {
                        ["role": $0.role.rawValue, "content": $0.content]
                    }
                    var body: [String: Any] = ["model": request.model, "input": input, "store": false, "stream": true]
                    if !instructions.isEmpty { body["instructions"] = instructions }
                    http.httpBody = try JSONSerialization.data(withJSONObject: body)
                    var completed = false
                    for try await line in StreamingClient().bytes(for: http, format: .sse) {
                        try Task.checkCancellation()
                        guard case .data(let data) = line, data != "[DONE]",
                              let bytes = data.data(using: .utf8),
                              let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                              let type = event["type"] as? String else { continue }
                        switch type {
                        case "response.output_text.delta":
                            if let delta = event["delta"] as? String { continuation.yield(TextDelta(text: delta)) }
                        case "response.completed": completed = true
                        case "response.failed", "response.incomplete", "error":
                            throw ChatGPTAuthError.message("ChatGPT could not complete this request. Check your plan usage and selected model.")
                        default: break
                        }
                        if completed { break }
                    }
                    try Task.checkCancellation()
                    guard completed else { throw ChatGPTAuthError.message("ChatGPT stream ended before completion. Please retry.") }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

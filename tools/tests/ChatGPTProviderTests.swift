// Offline request/stream regression tests. Compile with LLMClient.swift and ChatGPTProvider.swift.
import Foundation

enum ChatGPTAuthError: Error { case message(String) }
@MainActor final class ChatGPTAuth {
    static let shared = ChatGPTAuth()
    func accessToken(account: String) async throws -> String { "test-oauth-token" }
}
enum StreamLine { case data(String) }
enum StreamFormat { case sse }
struct StreamingClient {
    static var payloads: [String] = []
    static var captured: URLRequest?
    func bytes(for request: URLRequest, format: StreamFormat) -> AsyncThrowingStream<StreamLine, Error> {
        Self.captured = request
        return AsyncThrowingStream { continuation in
            for payload in Self.payloads { continuation.yield(.data(payload)) }
            continuation.finish()
        }
    }
}
@main struct ProviderTests {
    static func run(_ events: [String]) async throws -> String {
        StreamingClient.payloads = events
        var result = ""
        for try await delta in ChatGPTProvider(account: "test-account").stream(LLMRequest(
            model: "account-model", messages: [ChatMessage(role: .system, content: "Translate."),
                ChatMessage(role: .user, content: "你好")], temperature: 0.7, maxTokens: 64)) {
            result += delta.text
        }
        return result
    }
    static func main() async throws {
        let output = try await run([
            #"{"type":"response.created"}"#,
            #"{"type":"response.output_text.delta","delta":"Hello"}"#,
            #"{"type":"response.output_text.delta","delta":"!"}"#,
            #"{"type":"response.completed"}"#
        ])
        precondition(output == "Hello!")
        let request = StreamingClient.captured!
        precondition(request.url!.absoluteString == "https://api.openai.com/v1/responses")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-oauth-token")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["store"] as? Bool == false && body["stream"] as? Bool == true)
        precondition(body["instructions"] as? String == "Translate.")
        precondition(body["temperature"] == nil && body["max_output_tokens"] == nil)
        let input = body["input"] as! [[String: String]]
        precondition(input == [["role": "user", "content": "你好"]])
        var failures = 0
        for events in [[], [#"{"type":"response.output_text.delta","delta":"partial"}"#],
                       [#"{"type":"response.failed"}"#], [#"{"type":"response.incomplete"}"#],
                       [#"{"type":"error"}"#]] as [[String]] {
            do { _ = try await run(events) } catch { failures += 1 }
        }
        precondition(failures == 5)
        print("PASS: subscription request format, streaming output, and 5 incomplete/error cases")
    }
}

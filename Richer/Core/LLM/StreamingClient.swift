import Foundation

enum StreamLine: Sendable {
    case event(String)
    case data(String)
    case raw(String)
}

enum StreamFormat: Sendable {
    case sse
    case ndjson
}

struct StreamingClient {
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    func bytes(for request: URLRequest, format: StreamFormat) -> AsyncThrowingStream<StreamLine, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    NSLog("[Richer] LLM request: \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "?")")
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n"; if body.count > 2000 { break } }
                        throw LLMError.http(status: http.statusCode, body: body)
                    }
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        switch format {
                        case .sse:
                            if line.isEmpty { continue }
                            if line.hasPrefix("data:") {
                                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                                continuation.yield(.data(String(payload)))
                            } else if line.hasPrefix("event:") {
                                let name = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                                continuation.yield(.event(String(name)))
                            }
                        case .ndjson:
                            if !line.isEmpty {
                                continuation.yield(.raw(line))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

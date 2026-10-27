import AppKit
import CryptoKit
import Foundation
import Network
import Security

enum ChatGPTAuthError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct ChatGPTModel: Identifiable, Sendable {
    let id: String
    let displayName: String
}

struct ChatGPTCredentials: Codable {
    var clientID: String
    var subject: String
    var email: String
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Date
    var scopes: [String]
}

/// Each provider owns a separate registration. Credentials never enter UserDefaults.
@MainActor
final class ChatGPTAuth {
    static let shared = ChatGPTAuth()
    private var changingSessions: Set<String> = []
    private var refreshes: [String: Task<String, Error>] = [:]
    private let resource = "https://api.openai.com/v1"

    func credentials(_ account: String) -> ChatGPTCredentials? {
        guard let value = KeychainStore.shared.read(account: "chatgpt." + account),
              let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatGPTCredentials.self, from: data)
    }

    private func save(_ credentials: ChatGPTCredentials, account: String) throws {
        let data = try JSONEncoder().encode(credentials)
        guard let value = String(data: data, encoding: .utf8),
              KeychainStore.shared.save(value, account: "chatgpt." + account) else {
            throw ChatGPTAuthError.message("Could not save ChatGPT credentials in Keychain.")
        }
    }

    func signIn(account: String) async throws {
        guard changingSessions.insert(account).inserted else { throw ChatGPTAuthError.message("ChatGPT account update is already in progress.") }
        defer { changingSessions.remove(account) }
        if let pending = refreshes[account] { _ = try? await pending.value }
        let previous = credentials(account)
        let state = try Self.random()
        let nonce = try Self.random()
        let verifier = try Self.random()
        let callback = try ChatGPTCallback(state: state)
        defer { callback.stop() }
        let redirect = try await callback.start()
        let hostKey = "richer.chatgpt.hostID"
        let host = UserDefaults.standard.string(forKey: hostKey) ?? "urn:uuid:" + UUID().uuidString
        UserDefaults.standard.set(host, forKey: hostKey)
        var params = [
            "client_id": previous?.clientID ?? "dynamic_agent_client",
            "ext_agent_host_id": host, "response_type": "code",
            "redirect_uri": redirect, "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
            "resource": resource, "state": state, "nonce": nonce,
            "code_challenge_method": "S256",
            "code_challenge": Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        ]
        if previous == nil { params["agent_name_hint"] = "Richer" }
        if let hint = previous?.idToken { params["id_token_hint"] = hint }
        var url = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        url.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard NSWorkspace.shared.open(url.url!) else { throw ChatGPTAuthError.message("Could not open the sign-in browser.") }
        let result = try await callback.result()
        if let error = result["error"] { throw ChatGPTAuthError.message("ChatGPT authorization: " + error) }
        guard let code = result["code"],
              let clientID = result["client_id"] ?? previous?.clientID,
              clientID != "dynamic_agent_client", !clientID.isEmpty,
              previous == nil || clientID == previous?.clientID else {
            throw ChatGPTAuthError.message("ChatGPT returned an invalid client registration.")
        }
        let token = try await Self.token([
            "grant_type": "authorization_code", "client_id": clientID, "code": code,
            "code_verifier": verifier, "redirect_uri": redirect, "resource": resource
        ])
        guard let idToken = token["id_token"] as? String else { throw ChatGPTAuthError.message("ChatGPT did not return an identity token.") }
        let identity = try await ChatGPTIdentity.validate(idToken, clientID: clientID, nonce: nonce)
        if let previous, previous.subject != identity.subject {
            throw ChatGPTAuthError.message("This registration belongs to a different ChatGPT account. Add a new provider to switch accounts.")
        }
        var credentials = ChatGPTCredentials(clientID: clientID, subject: identity.subject,
            email: identity.email, expiresAt: .distantPast, scopes: [])
        try apply(token, to: &credentials)
        try Task.checkCancellation()
        try save(credentials, account: account)
    }

    func accessToken(account: String) async throws -> String {
        guard !changingSessions.contains(account) else { throw ChatGPTAuthError.message("ChatGPT account is being updated. Please retry after sign-in completes.") }
        if let task = refreshes[account] { return try await task.value }
        guard var credentials = credentials(account), let access = credentials.accessToken else {
            throw ChatGPTAuthError.message("Sign in with ChatGPT in Settings → Providers first.")
        }
        if credentials.expiresAt.timeIntervalSinceNow > 60 { return access }
        guard let refresh = credentials.refreshToken else { throw ChatGPTAuthError.message("Your ChatGPT session expired. Please sign in again.") }
        let task = Task { @MainActor in
            let token = try await Self.token(["grant_type": "refresh_token", "client_id": credentials.clientID,
                "refresh_token": refresh, "resource": resource])
            try apply(token, to: &credentials)
            try save(credentials, account: account)
            return credentials.accessToken!
        }
        refreshes[account] = task
        defer { refreshes[account] = nil }
        return try await task.value
    }

    func signOut(account: String) async throws {
        guard changingSessions.insert(account).inserted else { throw ChatGPTAuthError.message("ChatGPT account update is already in progress.") }
        defer { changingSessions.remove(account) }
        if let pending = refreshes[account] { _ = try? await pending.value }
        guard var credentials = credentials(account) else { return }
        var revokeError: Error?
        if let refresh = credentials.refreshToken {
            do {
                let config = try await Self.json(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!))
                guard let endpoint = config["revocation_endpoint"] as? String,
                      let url = URL(string: endpoint), url.scheme == "https", url.host == "auth.openai.com" else {
                    throw ChatGPTAuthError.message("Invalid ChatGPT revocation endpoint.")
                }
                _ = try await Self.send(Self.form(url: url, fields: ["token": refresh,
                    "token_type_hint": "refresh_token", "client_id": credentials.clientID]))
            } catch { revokeError = error }
        }
        credentials.accessToken = nil; credentials.refreshToken = nil; credentials.idToken = nil
        try save(credentials, account: account)
        if revokeError != nil {
            throw ChatGPTAuthError.message("Signed out locally. Remote revocation could not be confirmed; disconnect Richer in ChatGPT Settings.")
        }
    }

    func models(account: String) async throws -> [ChatGPTModel] {
        var request = URLRequest(url: URL(string: resource + "/models")!)
        request.setValue("Bearer " + (try await accessToken(account: account)), forHTTPHeaderField: "Authorization")
        let json = try await Self.json(request)
        let models = json["models"] as? [[String: Any]] ?? []
        return models.filter { $0["visibility"] as? String == "list" }.compactMap {
            guard let slug = $0["slug"] as? String else { return nil }
            return ChatGPTModel(id: slug, displayName: $0["display_name"] as? String ?? slug)
        }
    }

    private func apply(_ token: [String: Any], to credentials: inout ChatGPTCredentials) throws {
        let scopes = (token["scope"] as? String)?.split(separator: " ").map(String.init) ?? credentials.scopes
        guard scopes.contains("chatgpt.tokens.use.direct"), scopes.contains("resource.invoke") else {
            throw ChatGPTAuthError.message("ChatGPT plan usage was not authorized. Sign in again and allow plan usage.")
        }
        guard let access = token["access_token"] as? String, !access.isEmpty,
              let lifetime = token["expires_in"] as? Double, lifetime > 0,
              (token["token_type"] as? String)?.lowercased() == "bearer" else {
            throw ChatGPTAuthError.message("Invalid ChatGPT token response.")
        }
        credentials.accessToken = access
        credentials.refreshToken = token["refresh_token"] as? String ?? credentials.refreshToken
        credentials.idToken = token["id_token"] as? String ?? credentials.idToken
        credentials.expiresAt = Date().addingTimeInterval(lifetime)
        credentials.scopes = scopes
    }

    private static func token(_ fields: [String: String]) async throws -> [String: Any] {
        try await json(form(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!, fields: fields))
    }

    static func form(url: URL, fields: [String: String]) -> URLRequest {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }.map {
            $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }

    static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // OAuth responses may contain credentials; never include their body in diagnostics.
            throw ChatGPTAuthError.message("ChatGPT request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Please try signing in again.")
        }
        return data
    }

    static func json(_ request: URLRequest) async throws -> [String: Any] {
        let data = try await send(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChatGPTAuthError.message("Invalid ChatGPT response.")
        }
        return object
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ChatGPTAuthError.message("Could not generate secure sign-in parameters.")
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// A short-lived listener bound only to IPv4 loopback, with state verification.
@MainActor
private final class ChatGPTCallback {
    private let listener: NWListener
    private let state: String
    private let stream: AsyncThrowingStream<[String: String], Error>
    private let continuation: AsyncThrowingStream<[String: String], Error>.Continuation
    private var ready: CheckedContinuation<String, Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [NWConnection] = []

    init(state: String) throws {
        self.state = state
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    func start() async throws -> String {
        try await withCheckedThrowingContinuation { ready in
            self.ready = ready
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if let port = self.listener.port {
                            self.ready?.resume(returning: "http://127.0.0.1:\(port.rawValue)/auth/callback")
                            self.ready = nil
                        }
                    case .failed(let error):
                        self.ready?.resume(throwing: error); self.ready = nil
                        self.continuation.finish(throwing: error)
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    self.connections.append(connection)
                    connection.start(queue: .main)
                    self.receive(connection, accumulated: Data())
                }
            }
            listener.start(queue: .main)
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(180)) } catch { return }
                self?.continuation.finish(throwing: ChatGPTAuthError.message("ChatGPT sign-in timed out. Please try again."))
            }
        }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var bytes = accumulated; bytes.append(data ?? Data())
                guard bytes.count <= 16384, error == nil else { connection.cancel(); return }
                guard let text = String(data: bytes, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.receive(connection, accumulated: bytes) }
                    return
                }
                let parts = text.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard parts.count == 3, parts[0] == "GET",
                      let url = URLComponents(string: "http://127.0.0.1" + String(parts[1])),
                      url.path == "/auth/callback" else { connection.cancel(); return }
                var fields: [String: String] = [:]
                for item in url.queryItems ?? [] {
                    guard fields[item.name] == nil else { connection.cancel(); return }
                    fields[item.name] = item.value ?? ""
                }
                guard fields["state"] == self.state else { connection.cancel(); return }
                let body = "ChatGPT sign-in received. You can return to Richer."
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                self.continuation.yield(fields); self.continuation.finish()
            }
        }
    }

    func result() async throws -> [String: String] {
        for try await result in stream { try Task.checkCancellation(); return result }
        throw CancellationError()
    }

    func stop() {
        timeout?.cancel(); listener.cancel(); connections.forEach { $0.cancel() }
        continuation.finish()
    }
}

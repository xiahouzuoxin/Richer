import Foundation

/// Eudic dictionary backend.
/// - Lookup content: pulled from macOS Dictionary services (DCSCopyTextDefinition) — works
///   offline and uses whatever dictionaries the user has installed in Dictionary.app.
/// - Wordbook (生词本): reads/writes the user's Eudic word lists via api.frdic.com when an
///   API token is supplied. With no token, lookup still works; wordbook calls throw
///   DictionaryError.missingAuth.
struct EudicDictionary: DictionaryClient {
    let token: String?
    let language: String
    let displayName: String

    private static let baseURL = URL(string: "https://api.frdic.com/api/open/v1")!

    init(token: String?, language: String = "en", displayName: String = "Eudic") {
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.language = language
        self.displayName = displayName
    }

    var canWriteWordbook: Bool { token != nil }

    func lookup(_ word: String) async throws -> DictionaryEntry {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.notFound("") }

        if let entry = MacOSDictionaryBridge.entry(for: trimmed, sourceLabel: "macOS Dictionary") {
            return entry
        }
        // Either no installed dictionary contains the word, or no English dictionary is enabled.
        // Disambiguate by trying a definitely-common word.
        if MacOSDictionaryBridge.rawDefinition(for: "the") == nil {
            throw DictionaryError.noDictionaryInstalled
        }
        throw DictionaryError.notFound(trimmed)
    }

    func addToWordbook(_ word: String, language: String) async throws {
        guard let token else { throw DictionaryError.missingAuth }
        let categoryID = try await ensureDefaultCategoryID(token: token, language: language)

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("studylist/words"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "id": categoryID,
            "language": language,
            "words": [word]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DictionaryError.http(status: -1, body: "Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw DictionaryError.http(status: http.statusCode, body: bodyString)
        }
    }

    /// Validates the token by listing categories. Returns category names on success.
    func testConnection() async throws -> [String] {
        guard let token else { throw DictionaryError.missingAuth }
        let categories = try await listCategories(token: token, language: language)
        return categories.map(\.name)
    }

    // MARK: - Eudic API helpers

    private struct Category: Decodable, Sendable {
        let id: String
        let name: String
    }

    private struct CategoryListResponse: Decodable, Sendable {
        let data: [Category]
    }

    private func listCategories(token: String, language: String) async throws -> [Category] {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("studylist/category"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "language", value: language)]
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DictionaryError.http(status: -1, body: "Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DictionaryError.http(status: http.statusCode, body: body)
        }

        do {
            let decoded = try JSONDecoder().decode(CategoryListResponse.self, from: data)
            return decoded.data
        } catch {
            // Some responses are bare arrays. Try that as a fallback.
            if let bare = try? JSONDecoder().decode([Category].self, from: data) {
                return bare
            }
            throw DictionaryError.decoding(String(describing: error))
        }
    }

    /// Use the first category from the user's account (Eudic always has at least
    /// "默认生词本"). Cache lookups per token+language inside an actor so concurrent
    /// adds don't double-fetch.
    private func ensureDefaultCategoryID(token: String, language: String) async throws -> String {
        if let cached = await CategoryCache.shared.id(token: token, language: language) {
            return cached
        }
        let categories = try await listCategories(token: token, language: language)
        guard let first = categories.first else {
            throw DictionaryError.http(status: 404, body: "No category found in this Eudic account.")
        }
        await CategoryCache.shared.set(first.id, token: token, language: language)
        return first.id
    }
}

private actor CategoryCache {
    static let shared = CategoryCache()
    private var entries: [String: String] = [:]

    private func key(token: String, language: String) -> String { "\(token)|\(language)" }

    func id(token: String, language: String) -> String? {
        entries[key(token: token, language: language)]
    }

    func set(_ id: String, token: String, language: String) {
        entries[key(token: token, language: language)] = id
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

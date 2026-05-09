import Foundation

@MainActor
struct DictionaryService {
    let providerStore: ProviderStore

    func lookup(text: String, provider: ProviderConfig) async throws -> DictionaryEntry {
        let client = try providerStore.makeDictionaryClient(for: provider)
        // Dictionary lookups are by single token. Take just the first whitespace-delimited word
        // — phrases generally don't yield useful results from local dictionaries.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).first.map(String.init) ?? trimmed
        return try await client.lookup(firstWord)
    }

    func addToWordbook(word: String, provider: ProviderConfig) async throws {
        let client = try providerStore.makeDictionaryClient(for: provider)
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.addToWordbook(trimmed, language: "en")
    }
}

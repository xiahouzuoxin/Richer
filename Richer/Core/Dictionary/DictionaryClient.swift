import Foundation

protocol DictionaryClient: Sendable {
    func lookup(_ word: String) async throws -> DictionaryEntry
    func addToWordbook(_ word: String, language: String) async throws
    var canWriteWordbook: Bool { get }
}

enum DictionaryError: LocalizedError {
    case notFound(String)
    case missingAuth
    case http(status: Int, body: String)
    case decoding(String)
    case noDictionaryInstalled

    var errorDescription: String? {
        switch self {
        case .notFound(let word):
            String(localized: "No definition found for \"\(word)\".")
        case .missingAuth:
            String(localized: "Dictionary provider is missing authentication.")
        case .http(let status, let body):
            "HTTP \(status): \(body)"
        case .decoding(let msg):
            "Decoding error: \(msg)"
        case .noDictionaryInstalled:
            String(localized: "No English dictionary is enabled. Open Dictionary.app → Preferences and turn one on.")
        }
    }
}

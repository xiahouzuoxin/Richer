import Foundation

struct DictionaryEntry: Sendable, Equatable, Codable {
    var word: String
    var phonetics: [Phonetic]
    var senses: [Sense]
    var sourceLabel: String

    struct Phonetic: Sendable, Equatable, Codable {
        enum Region: String, Sendable, Equatable, Codable { case us, uk, generic }
        var region: Region
        var ipa: String
    }

    struct Sense: Sendable, Equatable, Codable {
        var partOfSpeech: String?
        var definition: String
        var examples: [String]
    }

    var isEmpty: Bool {
        phonetics.isEmpty && senses.allSatisfy { $0.definition.isEmpty }
    }

    var plainTextSummary: String {
        var lines: [String] = [word]
        if !phonetics.isEmpty {
            lines.append(phonetics.map { "[\($0.region.rawValue)] \($0.ipa)" }.joined(separator: "  "))
        }
        for (i, sense) in senses.enumerated() {
            let pos = sense.partOfSpeech.map { "\($0). " } ?? ""
            lines.append("\(i + 1). \(pos)\(sense.definition)")
            for ex in sense.examples {
                lines.append("    • \(ex)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum ActionResult: Sendable, Equatable {
    case empty
    case streamingText(String)
    case dictionary(DictionaryEntry)

    var isEmpty: Bool {
        switch self {
        case .empty: true
        case .streamingText(let s): s.isEmpty
        case .dictionary(let entry): entry.isEmpty
        }
    }

    var asText: String {
        switch self {
        case .empty: ""
        case .streamingText(let s): s
        case .dictionary(let entry): entry.plainTextSummary
        }
    }

    var streamingText: String {
        if case .streamingText(let s) = self { return s }
        return ""
    }
}

import Foundation

enum RefineTone: String, CaseIterable, Codable, Identifiable, Sendable {
    case original, professional, casual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: String(localized: "Original")
        case .professional: String(localized: "Professional")
        case .casual: String(localized: "Casual")
        }
    }
}

enum RefineLength: String, CaseIterable, Codable, Identifiable, Sendable {
    case original, concise, expand
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: String(localized: "Original")
        case .concise: String(localized: "Concise")
        case .expand: String(localized: "Expand")
        }
    }
}

struct RefineOptions: Codable, Equatable, Hashable, Sendable {
    var tone: RefineTone = .original
    var length: RefineLength = .original

    static let polish = RefineOptions()

    init(tone: RefineTone = .original, length: RefineLength = .original) {
        self.tone = tone
        self.length = length
    }

    /// Decode previously saved flat modes only at the persistence boundary.
    init(storedMode: String) {
        self.init(tone: RefineTone(rawValue: storedMode) ?? .original,
                  length: RefineLength(rawValue: storedMode) ?? .original)
    }

    init(from decoder: Decoder) throws {
        if let mode = try? decoder.singleValueContainer().decode(String.self) {
            self.init(storedMode: mode)
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tone: try values.decodeIfPresent(RefineTone.self, forKey: .tone) ?? .original,
                  length: try values.decodeIfPresent(RefineLength.self, forKey: .length) ?? .original)
    }

    var label: String {
        var parts = [String(localized: "Polish")]
        if tone != .original { parts.append(tone.label) }
        if length != .original { parts.append(length.label) }
        return parts.joined(separator: " · ")
    }
    var symbol: String { "sparkles" }
}

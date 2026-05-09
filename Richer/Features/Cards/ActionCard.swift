import Foundation

enum ActionKind: Codable, Equatable, Sendable {
    case refine(RefineMode)
    case translate
    case dictionary

    var label: String {
        switch self {
        case .refine(let mode): mode.label
        case .translate: String(localized: "Translate")
        case .dictionary: String(localized: "Dictionary")
        }
    }

    var symbol: String {
        switch self {
        case .refine(let mode): mode.symbol
        case .translate: "globe"
        case .dictionary: "book"
        }
    }

    var historyKind: HistoryKind {
        switch self {
        case .refine: .refine
        case .translate: .translate
        case .dictionary: .dictionary
        }
    }

    var compatibleProviderKinds: (ProviderKind) -> Bool {
        switch self {
        case .refine, .translate: { $0.isLLMKind }
        case .dictionary: { $0.isDictionaryKind }
        }
    }
}

struct ActionCard: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var providerID: UUID
    var action: ActionKind
    var enabled: Bool

    init(id: UUID = UUID(), providerID: UUID, action: ActionKind, enabled: Bool = true) {
        self.id = id
        self.providerID = providerID
        self.action = action
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, providerID, action, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.providerID = try c.decode(UUID.self, forKey: .providerID)
        self.action = try c.decode(ActionKind.self, forKey: .action)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

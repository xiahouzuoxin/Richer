import Foundation
import Observation

enum RefineMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case grammar
    case polish
    case professional
    case concise
    case casual

    var id: String { rawValue }
    var label: String {
        switch self {
        case .grammar: String(localized: "Grammar Fix")
        case .polish: String(localized: "Polish")
        case .professional: String(localized: "Professional")
        case .concise: String(localized: "Concise")
        case .casual: String(localized: "Casual")
        }
    }
    var symbol: String {
        switch self {
        case .grammar: "checkmark.circle"
        case .polish: "sparkles"
        case .professional: "briefcase"
        case .concise: "scissors"
        case .casual: "bubble.left"
        }
    }
}

struct RefineModeOverride: Codable, Equatable {
    var system: String
    var userTemplate: String
}

@Observable
@MainActor
final class RefineModeStore {
    private(set) var overrides: [RefineMode: RefineModeOverride] = [:]
    private let storageKey = "richer.refineModeOverrides.v1"

    init() { load() }

    func template(for mode: RefineMode) -> PromptTemplate {
        if let override = overrides[mode] {
            return PromptTemplate(system: override.system, userTemplate: override.userTemplate)
        }
        return DefaultPrompts.refine(for: mode)
    }

    func setOverride(_ override: RefineModeOverride?, for mode: RefineMode) {
        if let override {
            overrides[mode] = override
        } else {
            overrides.removeValue(forKey: mode)
        }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([RefineMode: RefineModeOverride].self, from: data) {
            overrides = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

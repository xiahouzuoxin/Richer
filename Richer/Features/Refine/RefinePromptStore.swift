import Foundation
import Observation

enum RefinePromptComponent: String, CaseIterable, Identifiable, Codable {
    case polish, professional, casual, concise, expand
    var id: Self { self }
    var label: String {
        switch self {
        case .polish: String(localized: "Base: Polish")
        case .professional: String(localized: "Tone: Professional")
        case .casual: String(localized: "Tone: Casual")
        case .concise: String(localized: "Length: Concise")
        case .expand: String(localized: "Length: Expand")
        }
    }
}

@Observable
@MainActor
final class RefinePromptStore {
    private(set) var instructions: [RefinePromptComponent: String] = [:]
    private let defaults: UserDefaults
    private let storageKey = "richer.refineInstructions.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([RefinePromptComponent: String].self, from: data) {
            instructions = saved
        }
    }

    func instruction(for component: RefinePromptComponent) -> String {
        instructions[component] ?? DefaultPrompts.refineInstruction(for: component)
    }

    func setInstruction(_ text: String?, for component: RefinePromptComponent) {
        instructions[component] = text
        if let data = try? JSONEncoder().encode(instructions) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func template(for options: RefineOptions) -> PromptTemplate {
        var components: [RefinePromptComponent] = [.polish]
        if options.tone == .professional { components.append(.professional) }
        if options.tone == .casual { components.append(.casual) }
        if options.length == .concise { components.append(.concise) }
        if options.length == .expand { components.append(.expand) }
        return DefaultPrompts.composedRefine(instructions: components.map { instruction(for: $0) })
    }
}

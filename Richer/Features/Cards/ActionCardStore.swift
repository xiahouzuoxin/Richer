import Foundation
import Observation

@Observable
@MainActor
final class ActionCardStore {
    private(set) var cards: [ActionCard] = []
    private let storageKey = "richer.cards.v1"

    init() {
        load()
    }

    func add(_ card: ActionCard) {
        cards.append(card)
        save()
    }

    func update(_ card: ActionCard) {
        guard let idx = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[idx] = card
        save()
    }

    func remove(_ id: UUID) {
        cards.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        cards.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func seedDefaultsIfEmpty(using providerID: UUID) {
        guard cards.isEmpty else { return }
        cards = [
            ActionCard(providerID: providerID, action: .refine(.polish)),
            ActionCard(providerID: providerID, action: .refine(.grammar)),
            ActionCard(providerID: providerID, action: .translate)
        ]
        save()
    }

    func addSuggestedDefaults(using providerID: UUID) {
        let existing = Set(cards.map { CardSignature(providerID: $0.providerID, action: $0.action) })
        let candidates: [ActionKind] = [.refine(.polish), .refine(.grammar), .translate]
        for action in candidates {
            let sig = CardSignature(providerID: providerID, action: action)
            if !existing.contains(sig) {
                cards.append(ActionCard(providerID: providerID, action: action))
            }
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ActionCard].self, from: data)
        else { return }
        cards = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

private struct CardSignature: Hashable {
    let providerID: UUID
    let action: ActionKind

    func hash(into hasher: inout Hasher) {
        hasher.combine(providerID)
        switch action {
        case .refine(let mode): hasher.combine("refine"); hasher.combine(mode)
        case .translate: hasher.combine("translate")
        }
    }
}

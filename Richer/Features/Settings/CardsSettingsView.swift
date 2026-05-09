import SwiftUI

struct CardsSettingsView: View {
    @Environment(Coordinator.self) private var coordinator
    @State private var selectedID: UUID?

    var body: some View {
        @Bindable var cardStore = coordinator.actionCardStore
        @Bindable var providerStore = coordinator.providerStore

        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(cardStore.cards) { card in
                        CardListRow(
                            card: card,
                            providers: providerStore.providers,
                            onToggleEnabled: { newValue in
                                var updated = card
                                updated.enabled = newValue
                                cardStore.update(updated)
                            }
                        )
                        .tag(card.id as UUID?)
                    }
                    .onMove { from, to in
                        cardStore.move(fromOffsets: from, toOffset: to)
                    }
                }
                .frame(width: 280)

                HStack(spacing: 8) {
                    Button { addCard() } label: { Image(systemName: "plus") }
                        .disabled(providerStore.providers.isEmpty)
                    Button {
                        if let id = selectedID {
                            cardStore.remove(id)
                            selectedID = nil
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selectedID == nil)
                    Spacer()
                    Button("Suggested") {
                        if let pid = providerStore.activeProvider?.id ?? providerStore.providers.first?.id {
                            cardStore.addSuggestedDefaults(using: pid)
                        }
                    }
                    .disabled(providerStore.providers.isEmpty)
                }
                .padding(8)
                .background(.thinMaterial)
            }

            Divider()

            if let id = selectedID, let card = cardStore.cards.first(where: { $0.id == id }) {
                CardEditor(card: card, providers: providerStore.providers) { updated in
                    cardStore.update(updated)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack {
                    Spacer()
                    if providerStore.providers.isEmpty {
                        Text("Add a provider in the Providers tab first.")
                            .foregroundStyle(.secondary)
                    } else if cardStore.cards.isEmpty {
                        Text("Click + or Suggested to create cards.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Select a card to edit.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func addCard() {
        guard let providerID = coordinator.providerStore.activeProvider?.id ?? coordinator.providerStore.providers.first?.id else { return }
        let new = ActionCard(providerID: providerID, action: .refine(.polish))
        coordinator.actionCardStore.add(new)
        selectedID = new.id
    }
}

private struct CardListRow: View {
    let card: ActionCard
    let providers: [ProviderConfig]
    let onToggleEnabled: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: card.action.symbol)
                .foregroundStyle(card.enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(card.action.label)
                    .font(.body)
                    .foregroundStyle(card.enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                Text(providers.first { $0.id == card.providerID }?.label ?? "Missing provider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { card.enabled },
                set: { onToggleEnabled($0) }
            ))
            .labelsHidden()
            .controlSize(.mini)
            .toggleStyle(.switch)
        }
    }
}

private struct CardEditor: View {
    let card: ActionCard
    let providers: [ProviderConfig]
    let onSave: (ActionCard) -> Void

    @State private var providerID: UUID
    @State private var actionTag: ActionTag
    @State private var refineMode: RefineMode

    enum ActionTag: String, CaseIterable, Identifiable {
        case refine, translate
        var id: String { rawValue }
        var label: String { self == .refine ? "Refine" : "Translate" }
    }

    init(card: ActionCard, providers: [ProviderConfig], onSave: @escaping (ActionCard) -> Void) {
        self.card = card
        self.providers = providers
        self.onSave = onSave
        _providerID = State(initialValue: card.providerID)
        switch card.action {
        case .refine(let mode):
            _actionTag = State(initialValue: .refine)
            _refineMode = State(initialValue: mode)
        case .translate:
            _actionTag = State(initialValue: .translate)
            _refineMode = State(initialValue: .polish)
        }
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $providerID) {
                    ForEach(providers) { provider in
                        Text(provider.label).tag(provider.id)
                    }
                }
            }
            Section("Action") {
                Picker("Action", selection: $actionTag) {
                    ForEach(ActionTag.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if actionTag == .refine {
                    Picker("Mode", selection: $refineMode) {
                        ForEach(RefineMode.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Save") {
                    let action: ActionKind = actionTag == .refine ? .refine(refineMode) : .translate
                    onSave(ActionCard(id: card.id, providerID: providerID, action: action))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .id(card.id)
    }
}

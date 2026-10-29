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
                        cardStore.addSuggestedDefaults(from: providerStore.providers)
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
                .id(card.id)
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
        let providers = coordinator.providerStore.providers
        // Prefer an LLM provider for the default Refine action; fall back to first available.
        let llmProvider = providers.first { $0.kind.isLLMKind } ?? providers.first
        guard let provider = llmProvider else { return }
        let new = ActionCard(providerID: provider.id, action: .refine(.polish))
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
    @Environment(Coordinator.self) private var coordinator
    let card: ActionCard
    let providers: [ProviderConfig]
    let onSave: (ActionCard) -> Void

    @State private var providerID: UUID
    @State private var actionTag: ActionTag
    @State private var refineOptions: RefineOptions

    enum ActionTag: String, CaseIterable, Identifiable {
        case translate, refine, reply, dictionary
        var id: String { rawValue }
        var label: String {
            switch self {
            case .refine: String(localized: "Refine")
            case .translate: String(localized: "Translate")
            case .reply: String(localized: "Reply")
            case .dictionary: String(localized: "Dictionary")
            }
        }

        func compatibleProviderKinds(_ kind: ProviderKind) -> Bool {
            switch self {
            case .refine, .translate, .reply: kind.isLLMKind
            case .dictionary: kind.isDictionaryKind
            }
        }
    }

    init(card: ActionCard, providers: [ProviderConfig], onSave: @escaping (ActionCard) -> Void) {
        self.card = card
        self.providers = providers
        self.onSave = onSave
        _providerID = State(initialValue: card.providerID)
        switch card.action {
        case .refine(let mode):
            _actionTag = State(initialValue: .refine)
            _refineOptions = State(initialValue: mode)
        case .translate:
            _actionTag = State(initialValue: .translate)
            _refineOptions = State(initialValue: .polish)
        case .reply:
            _actionTag = State(initialValue: .reply)
            _refineOptions = State(initialValue: .polish)
        case .dictionary:
            _actionTag = State(initialValue: .dictionary)
            _refineOptions = State(initialValue: .polish)
        }
    }

    private var filteredProviders: [ProviderConfig] {
        providers.filter { actionTag.compatibleProviderKinds($0.kind) }
    }

    var body: some View {
        Form {
            Section("Action") {
                Picker("Action", selection: $actionTag) {
                    ForEach(ActionTag.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .onChange(of: actionTag) { _, newTag in
                    // If the current provider isn't compatible with the new action,
                    // pick the first compatible one (or leave unchanged if none).
                    if let current = providers.first(where: { $0.id == providerID }),
                       !newTag.compatibleProviderKinds(current.kind),
                       let firstCompatible = providers.first(where: { newTag.compatibleProviderKinds($0.kind) }) {
                        providerID = firstCompatible.id
                    }
                }

                if actionTag == .refine {
                    RefineOptionsView(options: $refineOptions)
                }
            }
            Section("Provider") {
                if filteredProviders.isEmpty {
                    Label(
                        actionTag == .dictionary
                            ? "No dictionary provider configured. Add one in Settings → Providers."
                            : "No LLM provider configured. Add one in Settings → Providers.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else {
                    Picker("Provider", selection: $providerID) {
                        ForEach(filteredProviders) { provider in
                            Text(provider.label).tag(provider.id)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Save") {
                    let action: ActionKind
                    switch actionTag {
                    case .refine: action = .refine(refineOptions)
                    case .translate: action = .translate
                    case .reply: action = .reply
                    case .dictionary: action = .dictionary
                    }
                    onSave(ActionCard(id: card.id, providerID: providerID, action: action, enabled: card.enabled))
                }
                .buttonStyle(.borderedProminent)
                .disabled(filteredProviders.isEmpty)
            }
        }
        .formStyle(.grouped)
        .id(card.id)
    }
}

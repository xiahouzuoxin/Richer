import SwiftUI

struct ProvidersSettingsView: View {
    @Environment(Coordinator.self) private var coordinator
    @State private var selectedID: UUID?
    @State private var draft: ProviderDraft = .new()

    var body: some View {
        @Bindable var providerStore = coordinator.providerStore

        HStack(alignment: .top, spacing: 12) {
            VStack {
                List(selection: $selectedID) {
                    ForEach(providerStore.providers) { p in
                        HStack {
                            Image(systemName: providerStore.activeProviderID == p.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(providerStore.activeProviderID == p.id ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(p.label)
                                Text(p.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(p.id as UUID?)
                    }
                }
                .frame(width: 220)

                HStack {
                    Button {
                        let new = ProviderDraft.new()
                        draft = new
                        selectedID = nil
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let id = selectedID { providerStore.remove(id); selectedID = nil }
                    } label: { Image(systemName: "minus") }
                    .disabled(selectedID == nil)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            Divider()

            ProviderForm(
                draft: $draft,
                isEditing: selectedID != nil,
                onSave: { savedDraft in
                    saveDraft(savedDraft, providerStore: providerStore)
                },
                onSetActive: {
                    if let id = selectedID { providerStore.setActive(id) }
                }
            )
            .frame(maxWidth: .infinity)
        }
        .onChange(of: selectedID) { _, newID in
            if let id = newID, let provider = providerStore.providers.first(where: { $0.id == id }) {
                draft = ProviderDraft(from: provider)
            }
        }
    }

    private func saveDraft(_ d: ProviderDraft, providerStore: ProviderStore) {
        let cfg = d.toConfig()
        if let key = d.apiKey, !key.isEmpty, let keyId = cfg.keychainKeyId {
            KeychainStore.shared.save(key, account: keyId)
        }
        if providerStore.providers.contains(where: { $0.id == cfg.id }) {
            providerStore.update(cfg)
        } else {
            providerStore.add(cfg)
            selectedID = cfg.id
        }
    }
}

struct ProviderDraft {
    var id: UUID
    var kind: ProviderKind
    var label: String
    var baseURL: String
    var defaultModel: String
    var apiKey: String?
    var keychainKeyId: String?

    static func new() -> ProviderDraft {
        ProviderDraft(
            id: UUID(),
            kind: .openai,
            label: "OpenAI",
            baseURL: ProviderConfig.defaultBaseURL(for: .openai),
            defaultModel: ProviderKind.openai.defaultModels.first ?? "gpt-4o",
            apiKey: nil,
            keychainKeyId: UUID().uuidString
        )
    }

    init(id: UUID, kind: ProviderKind, label: String, baseURL: String, defaultModel: String, apiKey: String?, keychainKeyId: String?) {
        self.id = id; self.kind = kind; self.label = label
        self.baseURL = baseURL; self.defaultModel = defaultModel
        self.apiKey = apiKey; self.keychainKeyId = keychainKeyId
    }

    init(from cfg: ProviderConfig) {
        self.id = cfg.id
        self.kind = cfg.kind
        self.label = cfg.label
        self.baseURL = cfg.baseURL
        self.defaultModel = cfg.defaultModel
        self.keychainKeyId = cfg.keychainKeyId
        if let keyId = cfg.keychainKeyId {
            self.apiKey = KeychainStore.shared.read(account: keyId)
        }
    }

    func toConfig() -> ProviderConfig {
        ProviderConfig(
            id: id,
            kind: kind,
            label: label,
            baseURL: baseURL,
            defaultModel: defaultModel,
            keychainKeyId: keychainKeyId
        )
    }
}

private struct ProviderForm: View {
    @Binding var draft: ProviderDraft
    let isEditing: Bool
    let onSave: (ProviderDraft) -> Void
    let onSetActive: () -> Void

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Kind", selection: $draft.kind) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: draft.kind) { _, newKind in
                    let isDefault = ProviderKind.allCases.contains { draft.baseURL == ProviderConfig.defaultBaseURL(for: $0) }
                    if draft.baseURL.isEmpty || isDefault {
                        draft.baseURL = ProviderConfig.defaultBaseURL(for: newKind)
                    }
                    let allKindDefaults = Set(ProviderKind.allCases.flatMap { $0.defaultModels })
                    if draft.defaultModel.isEmpty || allKindDefaults.contains(draft.defaultModel) {
                        draft.defaultModel = newKind.defaultModels.first ?? ""
                    }
                    if draft.label.isEmpty || ProviderKind.allCases.map(\.displayName).contains(draft.label) {
                        draft.label = newKind.displayName
                    }
                }
                TextField("Label", text: $draft.label)
                TextField("Base URL", text: $draft.baseURL)
                TextField("Default model", text: $draft.defaultModel)
                if !draft.kind.defaultModels.isEmpty {
                    HStack {
                        Text("Suggested:")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(draft.kind.defaultModels, id: \.self) { m in
                            Button(m) { draft.defaultModel = m }
                                .buttonStyle(.link)
                        }
                    }
                }
                if let note = draft.kind.freeTierNote {
                    Label(note, systemImage: "gift")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if draft.kind.requiresAPIKey {
                Section("Authentication") {
                    SecureField("API key", text: Binding(
                        get: { draft.apiKey ?? "" },
                        set: { draft.apiKey = $0 }
                    ))
                    Text("Stored in macOS Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if isEditing {
                    Button("Set Active") { onSetActive() }
                }
                Spacer()
                Button("Save") { onSave(draft) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
    }

}

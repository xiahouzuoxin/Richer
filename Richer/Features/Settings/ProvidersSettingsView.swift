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
                .disabled(chatGPTBusy)
                .onChange(of: draft.kind) { _, newKind in
                    draft.apiKey = nil
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
                if draft.kind != .chatgpt {
                    TextField("Base URL", text: $draft.baseURL)
                }
                if draft.kind.isLLMKind {
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
                }
                if let note = draft.kind.freeTierNote {
                    Label(note, systemImage: "gift")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if draft.kind == .chatgpt {
                chatGPTAuthSection
            } else if draft.kind == .eudic {
                eudicAuthSection
            } else if draft.kind.requiresAPIKey {
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
                    .disabled(chatGPTBusy || (draft.kind == .chatgpt && draft.defaultModel.isEmpty))
            }
        }
        .formStyle(.grouped)
    }

    @State private var chatGPTTask: Task<Void, Never>?
    @State private var chatGPTBusy = false
    @State private var chatGPTStatus = ""
    @State private var chatGPTModels: [ChatGPTModel] = []
    @State private var chatGPTOperationID = UUID()
    @State private var chatGPTEmail = ""

    private var chatGPTAuthSection: some View {
        Section("ChatGPT account") {
            Text("Use your eligible ChatGPT plan. No API key required. Usage is subject to your plan and app limits.")
                .font(.caption).foregroundStyle(.secondary)
            if !chatGPTEmail.isEmpty { Label(chatGPTEmail, systemImage: "person.crop.circle") }
            HStack {
                Button("Continue with ChatGPT") { runChatGPTAction(signIn: true) }
                    .disabled(chatGPTBusy)
                if chatGPTBusy {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { chatGPTTask?.cancel() }
                } else if !chatGPTEmail.isEmpty {
                    Button("Refresh models") { runChatGPTAction(signIn: false) }
                    Button("Sign out") { signOutChatGPT() }
                }
            }
            if !chatGPTModels.isEmpty {
                Picker("Available models", selection: $draft.defaultModel) {
                    ForEach(chatGPTModels) { Text($0.displayName).tag($0.id) }
                }
            }
            if !chatGPTStatus.isEmpty { Text(chatGPTStatus).font(.caption).textSelection(.enabled) }
            Link("Manage ChatGPT usage and access", destination: URL(string: "https://chatgpt.com/#settings")!)
        }
        .task(id: draft.id) {
            chatGPTTask?.cancel()
            chatGPTOperationID = UUID(); chatGPTBusy = false
            chatGPTStatus = ""; chatGPTModels = []
            chatGPTEmail = draft.keychainKeyId.flatMap { ChatGPTAuth.shared.credentials($0) }
                .flatMap { $0.accessToken == nil ? nil : $0.email } ?? ""
        }
        .onDisappear { chatGPTTask?.cancel() }
    }

    private func runChatGPTAction(signIn: Bool) {
        let account = draft.keychainKeyId ?? UUID().uuidString
        draft.keychainKeyId = account
        let providerID = draft.id
        let operationID = UUID(); chatGPTOperationID = operationID
        chatGPTBusy = true; chatGPTStatus = ""
        chatGPTTask = Task { @MainActor in
            defer { if chatGPTOperationID == operationID { chatGPTBusy = false } }
            do {
                if signIn { try await ChatGPTAuth.shared.signIn(account: account) }
                try Task.checkCancellation()
                guard draft.id == providerID, draft.kind == .chatgpt else { return }
                chatGPTEmail = ChatGPTAuth.shared.credentials(account)?.email ?? ""
                let models = try await ChatGPTAuth.shared.models(account: account)
                try Task.checkCancellation()
                guard draft.id == providerID, draft.kind == .chatgpt else { return }
                chatGPTModels = models
                if !models.contains(where: { $0.id == draft.defaultModel }) { draft.defaultModel = models.first?.id ?? "" }
                chatGPTStatus = String(localized: "Connected. Save this provider and select Set Active to use it.")
            } catch is CancellationError {
                if chatGPTOperationID == operationID { chatGPTStatus = String(localized: "Sign-in cancelled.") }
            } catch {
                if chatGPTOperationID == operationID { chatGPTStatus = error.localizedDescription }
            }
        }
    }

    private func signOutChatGPT() {
        guard let account = draft.keychainKeyId else { return }
        let operationID = UUID(); chatGPTOperationID = operationID
        chatGPTBusy = true
        chatGPTTask = Task { @MainActor in
            defer {
                if chatGPTOperationID == operationID { chatGPTBusy = false; chatGPTEmail = ""; chatGPTModels = [] }
            }
            do {
                try await ChatGPTAuth.shared.signOut(account: account)
                if chatGPTOperationID == operationID { chatGPTStatus = String(localized: "Signed out.") }
            } catch {
                if chatGPTOperationID == operationID { chatGPTStatus = error.localizedDescription }
            }
        }
    }

    @State private var eudicTestState: EudicTestState = .idle

    private enum EudicTestState: Equatable {
        case idle
        case testing
        case ok([String])
        case failed(String)
    }

    @ViewBuilder
    private var eudicAuthSection: some View {
        Section("Account (optional)") {
            SecureField("API token", text: Binding(
                get: { draft.apiKey ?? "" },
                set: { draft.apiKey = $0; eudicTestState = .idle }
            ))
            VStack(alignment: .leading, spacing: 4) {
                Text("Lookup works without a token. Sign in to enable wordbook sync with your Eudic account.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("How to find your token (my.eudic.net/OpenAPI)", destination: URL(string: "https://my.eudic.net/OpenAPI/")!)
                    .font(.caption)
            }
            if let token = draft.apiKey, !token.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 8) {
                    Button("Test connection") { testEudicConnection(token: token) }
                        .controlSize(.small)
                        .disabled(eudicTestState == .testing)
                    switch eudicTestState {
                    case .idle:
                        EmptyView()
                    case .testing:
                        ProgressView().controlSize(.mini)
                    case .ok(let names):
                        Label("OK · \(names.count) categories", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func testEudicConnection(token: String) {
        eudicTestState = .testing
        Task {
            let client = EudicDictionary(token: token)
            do {
                let names = try await client.testConnection()
                await MainActor.run { eudicTestState = .ok(names) }
            } catch {
                await MainActor.run { eudicTestState = .failed(error.localizedDescription) }
            }
        }
    }
}

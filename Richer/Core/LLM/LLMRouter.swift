import Foundation
import Observation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case openai
    case deepseek
    case qwen
    case zhipu
    case openaiCompatible
    case ollama

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude: "Claude (Anthropic)"
        case .openai: "OpenAI"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen (DashScope)"
        case .zhipu: "Zhipu GLM"
        case .openaiCompatible: "OpenAI-compatible"
        case .ollama: "Ollama (local)"
        }
    }

    var requiresAPIKey: Bool {
        switch self { case .ollama: false; default: true }
    }

    /// First entry is treated as the recommended free-tier default.
    var defaultModels: [String] {
        switch self {
        case .claude: ["claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5-20251001"]
        case .openai: ["gpt-4o-mini", "gpt-4o"]
        case .deepseek: ["deepseek-chat", "deepseek-reasoner"]
        case .qwen: ["qwen-turbo", "qwen-plus", "qwen-max"]
        case .zhipu: ["glm-4-flash", "glm-4-plus", "glm-4-air"]   // glm-4-flash is free
        case .openaiCompatible: []
        case .ollama: ["llama3.2", "qwen2.5"]
        }
    }

    var freeTierNote: String? {
        switch self {
        case .qwen: "qwen-turbo includes a generous free quota."
        case .zhipu: "glm-4-flash is free of charge."
        case .ollama: "Runs locally — no API cost."
        default: nil
        }
    }
}

struct ProviderConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: ProviderKind
    var label: String
    var baseURL: String
    var defaultModel: String
    var keychainKeyId: String?

    static func defaultBaseURL(for kind: ProviderKind) -> String {
        switch kind {
        case .claude: "https://api.anthropic.com/v1"
        case .openai: "https://api.openai.com/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .openaiCompatible: ""
        case .ollama: "http://127.0.0.1:11434"
        }
    }
}

@Observable
@MainActor
final class ProviderStore {
    private(set) var providers: [ProviderConfig] = []
    var activeProviderID: UUID?

    private let storageKey = "richer.providers.v1"
    private let activeKey = "richer.activeProviderID.v1"

    init() {
        load()
    }

    var activeProvider: ProviderConfig? {
        guard let id = activeProviderID else { return providers.first }
        return providers.first { $0.id == id } ?? providers.first
    }

    func add(_ provider: ProviderConfig) {
        providers.append(provider)
        if activeProviderID == nil { activeProviderID = provider.id }
        save()
    }

    func update(_ provider: ProviderConfig) {
        guard let idx = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[idx] = provider
        save()
    }

    func remove(_ id: UUID) {
        providers.removeAll { $0.id == id }
        if activeProviderID == id { activeProviderID = providers.first?.id }
        save()
    }

    func setActive(_ id: UUID) {
        activeProviderID = id
        save()
    }

    func makeClient(for provider: ProviderConfig) throws -> LLMClient {
        switch provider.kind {
        case .claude:
            let key = try requireKey(for: provider)
            let url = URL(string: provider.baseURL) ?? URL(string: "https://api.anthropic.com/v1")!
            return ClaudeProvider(apiKey: key, baseURL: url)
        case .openai, .deepseek, .qwen, .zhipu, .openaiCompatible:
            let key = try requireKey(for: provider)
            guard let url = URL(string: provider.baseURL.isEmpty
                                ? ProviderConfig.defaultBaseURL(for: provider.kind)
                                : provider.baseURL)
            else { throw LLMError.invalidEndpoint }
            return OpenAICompatibleProvider(baseURL: url, apiKey: key)
        case .ollama:
            let url = URL(string: provider.baseURL) ?? URL(string: "http://127.0.0.1:11434")!
            return OllamaProvider(baseURL: url)
        }
    }

    private func requireKey(for provider: ProviderConfig) throws -> String {
        guard let keyId = provider.keychainKeyId,
              let key = KeychainStore.shared.read(account: keyId), !key.isEmpty
        else { throw LLMError.missingAPIKey }
        return key
    }

    func activeClient() throws -> (LLMClient, ProviderConfig) {
        guard let provider = activeProvider else { throw LLMError.noActiveProvider }
        return (try makeClient(for: provider), provider)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ProviderConfig].self, from: data) {
            providers = decoded
        }
        if let activeRaw = defaults.string(forKey: activeKey), let uuid = UUID(uuidString: activeRaw) {
            activeProviderID = uuid
        }
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: storageKey)
        }
        if let id = activeProviderID {
            defaults.set(id.uuidString, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
    }
}

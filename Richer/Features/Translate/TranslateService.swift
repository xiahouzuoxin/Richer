import Foundation
import NaturalLanguage
import Observation

@Observable
@MainActor
final class TranslateSettings {
    var primaryTarget: String
    var secondaryTarget: String

    private let primaryKey = "richer.translate.primary"
    private let secondaryKey = "richer.translate.secondary"

    init() {
        let defaults = UserDefaults.standard
        self.primaryTarget = defaults.string(forKey: primaryKey) ?? "en"
        self.secondaryTarget = defaults.string(forKey: secondaryKey) ?? "zh"
    }

    func setPrimary(_ code: String) {
        primaryTarget = code
        UserDefaults.standard.set(code, forKey: primaryKey)
    }
    func setSecondary(_ code: String) {
        secondaryTarget = code
        UserDefaults.standard.set(code, forKey: secondaryKey)
    }
}

@MainActor
struct TranslateService {
    let providerStore: ProviderStore
    let settings: TranslateSettings

    /// Resolve the target language considering an explicit override.
    /// `override` of nil means "auto" (use primary/secondary fallback against detected source).
    func resolveTargetLanguage(for text: String, override: String?) -> String {
        if let override { return override }
        let detected = LanguageDetector.detect(text)?.rawValue
        if let detected, detected == settings.primaryTarget {
            return settings.secondaryTarget
        }
        return settings.primaryTarget
    }

    func stream(text: String, provider: ProviderConfig, targetOverride: String? = nil) throws -> (AsyncThrowingStream<TextDelta, Error>, String) {
        let target = resolveTargetLanguage(for: text, override: targetOverride)
        let client = try providerStore.makeClient(for: provider)
        let context = [
            "targetLanguage": LanguageDetector.displayName(for: target)
        ]
        let messages = DefaultPrompts.translate.messages(for: text, additionalContext: context)
        let request = LLMRequest(model: provider.defaultModel, messages: messages, temperature: 0.2)
        return (client.stream(request), target)
    }
}

import Foundation
import NaturalLanguage

enum LanguageDetector {
    static func detect(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    static func displayName(for code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code) ?? code
    }

    /// Strip a regional subtag so `NLLanguageRecognizer`'s output ("zh-Hans", "zh-Hant",
    /// "en-US"…) can be compared against the bare codes the user picks from the language
    /// picker ("zh", "en", …). Without this, Chinese input never matches a "zh" primary
    /// target and the auto-target rule misfires.
    static func baseLanguageCode(_ code: String) -> String {
        if let hyphen = code.firstIndex(of: "-") {
            return String(code[..<hyphen])
        }
        return code
    }
}

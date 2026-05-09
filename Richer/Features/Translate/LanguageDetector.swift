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
}

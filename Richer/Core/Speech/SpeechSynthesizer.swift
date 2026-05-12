import AVFoundation
import Foundation
import Observation

/// Process-wide TTS wrapper around `AVSpeechSynthesizer`. UI surfaces observe `shared`
/// to render their speaker icons in idle vs. playing state. Only one utterance plays
/// at a time globally — starting a new `play(_:)` cancels the previous one.
@Observable
@MainActor
final class SpeechSynthesizer: NSObject {
    static let shared = SpeechSynthesizer()

    /// True while audio is playing (between `didStart` and `didFinish` / `didCancel`).
    private(set) var isPlaying: Bool = false

    /// Whatever string the current utterance was created from. Lets observing views
    /// decide "am I the row whose text is playing right now?" so only that row's
    /// speaker icon flips to the "stop" state.
    private(set) var currentText: String?

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Start reading `text` aloud. Auto-detects language and picks the matching voice.
    /// Calling while another utterance is playing cancels the previous and starts the new.
    func play(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = bestVoice(for: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        currentText = trimmed
        isPlaying = true
        synthesizer.speak(utterance)
    }

    /// Cancel the active utterance, if any. Safe to call when nothing is playing.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying = false
        currentText = nil
    }

    /// Toggle: if `text` is currently playing, stop. Otherwise start playing `text`.
    /// The natural binding for a speaker icon that flips between idle and "stop".
    func toggle(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isPlaying, currentText == trimmed {
            stop()
        } else {
            play(trimmed)
        }
    }

    /// True when this `text` is the one currently being read. Use it to decide whether
    /// to render `speaker.fill` (stop affordance) vs `speaker.wave.2` (start affordance).
    func isPlaying(_ text: String) -> Bool {
        isPlaying && currentText == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Voice selection

    private func bestVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let detected = LanguageDetector.detect(text)?.rawValue
        let baseCode = detected.map { LanguageDetector.baseLanguageCode($0) } ?? Locale.current.language.languageCode?.identifier ?? "en"
        // Map language codes to BCP-47 voice tags AVSpeechSynthesisVoice understands.
        let preferred: String
        switch baseCode {
        case "zh":
            // Detector gives "zh-Hans" / "zh-Hant"; pick the voice that matches.
            preferred = (detected == "zh-Hant") ? "zh-TW" : "zh-CN"
        case "ja": preferred = "ja-JP"
        case "ko": preferred = "ko-KR"
        case "fr": preferred = "fr-FR"
        case "de": preferred = "de-DE"
        case "es": preferred = "es-ES"
        case "it": preferred = "it-IT"
        case "ru": preferred = "ru-RU"
        case "pt": preferred = "pt-BR"
        case "en": preferred = "en-US"
        default: preferred = baseCode
        }

        // Prefer enhanced/premium quality when installed; fall back to default.
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(preferred) || $0.language.hasPrefix(baseCode)
        }
        if let enhanced = voices.first(where: { $0.quality == .premium })
                       ?? voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: preferred) ?? AVSpeechSynthesisVoice(language: baseCode)
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isPlaying = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentText = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentText = nil
        }
    }
}

import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class CaptionViewModel {
    /// Full text the view renders. The view wraps this in a ScrollView and pins the
    /// bottom edge, so visually only the trailing lines are seen — without any
    /// ellipsis indicator.
    private(set) var displayText: String = ""
    var errorMessage: String?

    /// User-tweakable just like the input window's dictation control.
    var sttLocale: String = CaptionViewModel.defaultLocale()
    var sttDeviceUID: String? = nil

    /// Concatenation of all *finalized* phrases seen so far. SFSpeech finalizes after
    /// ~1 minute of speech or after a long pause; we restart immediately to keep
    /// captioning continuous, accumulating finals here. Capped to keep memory bounded.
    private var stableText: String = ""
    /// The currently-streaming partial that hasn't been finalized yet.
    private var currentPartial: String = ""

    private let recognizer = SpeechRecognizer()
    /// Set when the controller is tearing the panel down. Suppresses auto-restart.
    private var isStopping = false
    /// Set when the user clicks the mic button to pause. Suppresses auto-restart so
    /// the user-initiated stop sticks. Reset back to false when the user re-engages.
    /// Without this, the natural-phrase-boundary auto-restart in `onFinal` would
    /// immediately re-arm and the mic button would appear broken.
    private var userPaused = false

    var isRecording: Bool { recognizer.isRecording }

    /// Cap on the stable buffer so a multi-hour session can't OOM. Anything older
    /// rolls off silently (no ellipsis indicator); the user perceives only the
    /// recent lines through the ScrollView's bottom anchor.
    private let stableCap = 800

    /// Start dictating immediately on creation — opening the bar is the user's intent.
    init() {
        startRecording()
    }

    /// Stop any in-flight task. Called from the controller before tearing the panel down.
    func tearDown() {
        isStopping = true
        recognizer.stop()
    }

    /// Toggle from the mic button. Click to pause / resume mid-session.
    func toggleMic() {
        if recognizer.isRecording {
            userPaused = true
            recognizer.stop()
        } else {
            userPaused = false
            startRecording()
        }
    }

    // MARK: - Internal

    private func startRecording() {
        errorMessage = nil
        if !MicrophoneGuard.isTrusted {
            MicrophoneGuard.requestTrust { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.startRecording() }
                    else { self.errorMessage = SpeechRecognitionError.microphoneDenied.errorDescription }
                }
            }
            return
        }
        if !SpeechRecognitionGuard.isTrusted {
            SpeechRecognitionGuard.requestTrust { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.startRecording() }
                    else { self.errorMessage = SpeechRecognitionError.speechRecognitionDenied.errorDescription }
                }
            }
            return
        }
        recognizer.start(
            locale: sttLocale,
            deviceUID: sttDeviceUID,
            onPartial: { [weak self] partial in
                guard let self else { return }
                self.currentPartial = partial
                self.refreshDisplay()
            },
            onFinal: { [weak self] final in
                guard let self else { return }
                // Fold the final into the stable buffer, then auto-restart so captioning
                // keeps flowing past SFSpeech's ~60s phrase boundary. Unless the user
                // explicitly hit the mic button to stop or we're tearing down.
                if !final.isEmpty {
                    let separator = self.stableText.isEmpty ? "" : " "
                    self.stableText += separator + final
                    if self.stableText.count > self.stableCap {
                        // Silently drop the oldest content, snapping to a word boundary
                        // so we never slice mid-word. No ellipsis prefix — the user
                        // sees only the recent lines through the ScrollView.
                        var trimmed = String(self.stableText.suffix(self.stableCap))
                        if let firstSpace = trimmed.firstIndex(of: " ") {
                            trimmed = String(trimmed[trimmed.index(after: firstSpace)...])
                        }
                        self.stableText = trimmed
                    }
                }
                self.currentPartial = ""
                self.refreshDisplay()
                if let err = self.recognizer.lastError {
                    self.errorMessage = err
                    return
                }
                if self.isStopping || self.userPaused {
                    // Don't fight a deliberate stop with an immediate re-arm.
                    return
                }
                // Natural phrase boundary — re-arm so captioning flows past SFSpeech's
                // ~60s utterance limit without user intervention.
                self.startRecording()
            }
        )
    }

    private func refreshDisplay() {
        if stableText.isEmpty {
            displayText = currentPartial
        } else if currentPartial.isEmpty {
            displayText = stableText
        } else {
            displayText = stableText + " " + currentPartial
        }
    }

    private static func defaultLocale() -> String {
        let base = Locale.current.language.languageCode?.identifier ?? "en"
        switch base {
        case "zh":
            return (Locale.current.language.script?.identifier == "Hant") ? "zh-TW" : "zh-CN"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "it": return "it-IT"
        case "ru": return "ru-RU"
        case "pt": return "pt-BR"
        default: return "en-US"
        }
    }
}

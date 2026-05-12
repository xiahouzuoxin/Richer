import AppKit
import Speech

enum SpeechRecognitionGuard {
    static var isTrusted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Prompts the user the first time. Bounces back to main from the system's
    /// callback queue so UI updates are safe in the closure.
    static func requestTrust(_ completion: @escaping (Bool) -> Void = { _ in }) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    static func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }
}

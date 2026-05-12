import AppKit
import AVFoundation

enum MicrophoneGuard {
    static var isTrusted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Prompts the user the first time. The closure fires on a background queue
    /// once the user picks; bounce back to main if you need to touch UI.
    static func requestTrust(_ completion: @escaping (Bool) -> Void = { _ in }) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            completion(granted)
        }
    }

    static func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

import AppKit
import CoreGraphics

enum ScreenCaptureGuard {
    static var isTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the macOS Screen Recording permission dialog. Returns the post-prompt
    /// state synchronously, but the user's choice may not be reflected immediately —
    /// the prompt is async, and you typically need to re-check after the user grants.
    @discardableResult
    static func requestTrust() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

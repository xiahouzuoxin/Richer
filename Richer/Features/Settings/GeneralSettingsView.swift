import SwiftUI
import AppKit

struct GeneralSettingsView: View {
    @AppStorage("richer.showDockIcon") private var showDockIcon: Bool = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show Dock icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    }
                Text("When off, Richer lives only in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LanguageSection()
            }

            Section("Permissions") {
                AccessibilitySection()
            }
        }
        .formStyle(.grouped)
    }
}

private struct LanguageSection: View {
    @State private var selection: String = LanguageSection.currentSelection()

    static func currentSelection() -> String {
        guard let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              let first = langs.first else {
            return "system"
        }
        if first.hasPrefix("zh") { return "zh-Hans" }
        if first.hasPrefix("en") { return "en" }
        return "system"
    }

    var body: some View {
        Picker("Language", selection: $selection) {
            Text("Follow System").tag("system")
            Text(verbatim: "English").tag("en")
            Text(verbatim: "简体中文").tag("zh-Hans")
        }
        .onChange(of: selection) { _, newValue in
            apply(newValue)
        }
    }

    private func apply(_ value: String) {
        if value == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([value], forKey: "AppleLanguages")
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "Restart Required")
        alert.informativeText = String(localized: "Language change takes effect after restarting Richer.")
        alert.addButton(withTitle: String(localized: "Restart Now"))
        alert.addButton(withTitle: String(localized: "Later"))

        if alert.runModal() == .alertFirstButtonReturn {
            relaunch()
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

private struct AccessibilitySection: View {
    @State private var isTrusted: Bool = AccessibilityGuard.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isTrusted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                        .font(.body.weight(.medium))
                    Text(isTrusted ? "Granted — selection-hotkey workflow enabled."
                                   : "Required for the selection-hotkey workflow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Re-check") {
                    isTrusted = AccessibilityGuard.isTrusted
                }
            }
            HStack {
                Button("Open Privacy Settings") {
                    AccessibilityGuard.openSystemPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
                Button("Request Prompt") {
                    AccessibilityGuard.requestTrust()
                    isTrusted = AccessibilityGuard.isTrusted
                }
            }
            Text("Note: each Xcode rebuild changes the app's signature and invalidates the previous grant. If Richer keeps asking for permission, remove the existing 'Richer' entry from the Accessibility list and add this build's `Richer.app` again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { isTrusted = AccessibilityGuard.isTrusted }
    }
}

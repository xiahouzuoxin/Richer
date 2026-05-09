import SwiftUI

struct TranslateSettingsView: View {
    @Environment(Coordinator.self) private var coordinator

    private let languageCodes: [String] = [
        "en", "zh", "ja", "ko", "es", "fr", "de", "pt", "ru", "it"
    ]

    var body: some View {
        @Bindable var settings = coordinator.translateSettings
        Form {
            Section("Targets") {
                Picker("Primary target", selection: Binding(
                    get: { settings.primaryTarget },
                    set: { settings.setPrimary($0) }
                )) {
                    ForEach(languageCodes, id: \.self) { code in
                        Text(LanguageDetector.displayName(for: code)).tag(code)
                    }
                }
                Picker("Secondary target", selection: Binding(
                    get: { settings.secondaryTarget },
                    set: { settings.setSecondary($0) }
                )) {
                    ForEach(languageCodes, id: \.self) { code in
                        Text(LanguageDetector.displayName(for: code)).tag(code)
                    }
                }
                Text("If detected source matches the primary, Richer translates to the secondary instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

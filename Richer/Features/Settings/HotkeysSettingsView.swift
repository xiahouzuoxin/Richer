import SwiftUI
import KeyboardShortcuts

struct HotkeysSettingsView: View {
    var body: some View {
        Form {
            Section("Selection") {
                KeyboardShortcuts.Recorder("Refine selection", name: .selectionRefine)
                KeyboardShortcuts.Recorder("Translate selection", name: .selectionTranslate)
            }
            Section("Input window") {
                KeyboardShortcuts.Recorder("Open input window", name: .inputWindow)
            }
        }
        .formStyle(.grouped)
    }
}

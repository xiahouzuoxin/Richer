import SwiftUI
import KeyboardShortcuts

struct HotkeysSettingsView: View {
    var body: some View {
        Form {
            Section("Selection") {
                KeyboardShortcuts.Recorder("Refine selection", name: .selectionRefine)
                KeyboardShortcuts.Recorder("Translate selection", name: .selectionTranslate)
                KeyboardShortcuts.Recorder("Look up selection", name: .selectionDictionary)
            }
            Section("Screen") {
                KeyboardShortcuts.Recorder("Capture & lookup region", name: .screenshotOCR)
            }
            Section("Captions") {
                KeyboardShortcuts.Recorder("Toggle captions bar", name: .captionBar)
            }
            Section("Input window") {
                KeyboardShortcuts.Recorder("Open input window", name: .inputWindow)
            }
        }
        .formStyle(.grouped)
    }
}

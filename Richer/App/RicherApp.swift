import SwiftUI
import SwiftData
import KeyboardShortcuts

@main
struct RicherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.coordinator)
                .modelContainer(appDelegate.modelContainer)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsScene()
                .environment(appDelegate.coordinator)
                .modelContainer(appDelegate.modelContainer)
                .frame(minWidth: 640, minHeight: 460)
        }
    }
}

struct MenuBarContent: View {
    @Environment(Coordinator.self) private var coordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            menuRow(
                title: "Open Input Window",
                shortcut: KeyboardShortcuts.getShortcut(for: .inputWindow),
                action: { coordinator.openInputWindow(intent: .refine) }
            )

            menuRow(
                title: "Translate Selection",
                shortcut: KeyboardShortcuts.getShortcut(for: .selectionTranslate),
                action: nil
            )
            menuRow(
                title: "Refine Selection",
                shortcut: KeyboardShortcuts.getShortcut(for: .selectionRefine),
                action: nil
            )
            menuRow(
                title: "Look Up Selection",
                shortcut: KeyboardShortcuts.getShortcut(for: .selectionDictionary),
                action: nil
            )
            menuRow(
                title: "Capture & Look Up",
                shortcut: KeyboardShortcuts.getShortcut(for: .screenshotOCR),
                action: nil
            )
            menuRow(
                title: "Captions Bar",
                shortcut: KeyboardShortcuts.getShortcut(for: .captionBar),
                action: { coordinator.openCaptionBar() }
            )

            Divider()

            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Button("Quit Richer") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 240)
    }

    @ViewBuilder
    private func menuRow(title: LocalizedStringKey, shortcut: KeyboardShortcuts.Shortcut?, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                HStack {
                    Text(title)
                    Spacer()
                    if let shortcut {
                        Text(verbatim: "\(shortcut)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } else {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                if let shortcut {
                    Text(verbatim: "\(shortcut)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("not set")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
    }
}

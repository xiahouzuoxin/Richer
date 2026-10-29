import SwiftUI

struct SettingsScene: View {
    @Environment(Coordinator.self) private var coordinator

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            ProvidersSettingsView()
                .tabItem { Label("Providers", systemImage: "server.rack") }

            CardsSettingsView()
                .tabItem { Label("Cards", systemImage: "rectangle.stack") }

            WritingSettingsView()
                .tabItem { Label("Writing", systemImage: "text.bubble") }

            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .padding(20)
    }
}

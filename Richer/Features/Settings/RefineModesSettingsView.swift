import SwiftUI

struct RefineModesSettingsView: View {
    @Environment(Coordinator.self) private var coordinator
    @State private var selected: RefineMode = .grammar
    @State private var systemText: String = ""
    @State private var userText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $selected) {
                ForEach(RefineMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text("System prompt").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $systemText)
                .frame(minHeight: 80)
                .border(.separator)

            Text("User prompt template (use {{text}})").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $userText)
                .frame(minHeight: 80)
                .border(.separator)

            HStack {
                Button("Restore default") {
                    coordinator.refineModeStore.setOverride(nil, for: selected)
                    let t = DefaultPrompts.refine(for: selected)
                    systemText = t.system
                    userText = t.userTemplate
                }
                Spacer()
                Button("Save") {
                    coordinator.refineModeStore.setOverride(
                        RefineModeOverride(system: systemText, userTemplate: userText),
                        for: selected
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(8)
        .onAppear { loadFor(selected) }
        .onChange(of: selected) { _, newValue in loadFor(newValue) }
    }

    private func loadFor(_ mode: RefineMode) {
        let template = coordinator.refineModeStore.template(for: mode)
        systemText = template.system
        userText = template.userTemplate
    }
}

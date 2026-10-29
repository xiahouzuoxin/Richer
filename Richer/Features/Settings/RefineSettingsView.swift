import SwiftUI

struct RefineSettingsView: View {
    @Environment(Coordinator.self) private var coordinator
    @State private var selected: RefinePromptComponent = .polish
    @State private var instruction = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Polish fixes grammar, spelling, and punctuation while improving clarity and flow. Tone and length adjustments can be combined.")
                    .font(.callout).foregroundStyle(.secondary)

                Picker("Prompt component", selection: $selected) {
                    ForEach(RefinePromptComponent.allCases) { Text($0.label).tag($0) }
                }
                Text("Writing instruction").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $instruction)
                    .frame(height: 120).border(.separator)
                Text("Selected instructions are combined automatically. Input text and shared language, meaning, and output rules are added by Refine.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Restore default") {
                        coordinator.refinePromptStore.setInstruction(nil, for: selected)
                        loadInstruction()
                    }
                    Spacer()
                    Button("Save") {
                        coordinator.refinePromptStore.setInstruction(instruction, for: selected)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(8)
        }
        .onAppear { loadInstruction() }
        .onChange(of: selected) { _, _ in loadInstruction() }
    }

    private func loadInstruction() {
        instruction = coordinator.refinePromptStore.instruction(for: selected)
    }
}

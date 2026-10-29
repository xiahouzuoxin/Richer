import SwiftUI

struct WritingSettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case translate, refine, reply
        var id: Self { self }
        var label: String {
            switch self {
            case .translate: String(localized: "Translate")
            case .refine: String(localized: "Refine")
            case .reply: String(localized: "Reply")
            }
        }
    }
    @State private var selection: Section = .translate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Writing", selection: $selection) {
                ForEach(Section.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Group {
                switch selection {
                case .translate:
                    TranslateSettingsView()
                case .refine:
                    RefineSettingsView()
                case .reply:
                    ReplySettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ReplySettingsView: View {
    @Environment(Coordinator.self) private var coordinator
    @State private var instruction = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replies are concise, polite, and accurate by default. Customize the writing instructions below; reply notes can guide each individual answer.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Reply prompt").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $instruction)
                .frame(minHeight: 150)
                .border(.separator)
            Text("These instructions apply to both selection popups and input cards. Reply drafts use the message's language unless your reply notes request another language.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Restore default") {
                    coordinator.replySettings.restoreDefault()
                    instruction = coordinator.replySettings.instruction
                    saved = true
                }
                Spacer()
                if saved { Text("Saved").font(.caption).foregroundStyle(.secondary) }
                Button("Save") {
                    coordinator.replySettings.saveInstruction(instruction)
                    instruction = coordinator.replySettings.instruction
                    saved = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
        .onAppear { instruction = coordinator.replySettings.instruction }
        .onChange(of: instruction) { _, value in
            if value != coordinator.replySettings.instruction { saved = false }
        }
    }
}

import SwiftUI
import SwiftData
import AppKit

struct PopupView: View {
    @Bindable var viewModel: PopupViewModel
    @Environment(\.modelContext) private var modelContext
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            actionBar
            Divider()
            content
        }
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .frame(width: 460)
        .onAppear {
            viewModel.runIfNeeded(modelContext: modelContext)
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: headerSymbol)
                .foregroundStyle(.tint)
            Text(headerTitle)
                .font(.subheadline.weight(.medium))
            if !viewModel.providerLabelInUse.isEmpty {
                Text("• \(viewModel.providerLabelInUse)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var headerSymbol: String {
        switch viewModel.intent {
        case .refine: "wand.and.stars"
        case .translate: "globe"
        case .dictionary: "book"
        }
    }

    private var headerTitle: LocalizedStringKey {
        switch viewModel.intent {
        case .refine: "Richer • Refine"
        case .translate: "Richer • Translate"
        case .dictionary: "Richer • Dictionary"
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { viewModel.intent },
                set: { newValue in viewModel.switchTo(newValue, modelContext: modelContext) }
            )) {
                Text("Refine").tag(WriteIntent.refine)
                Text("Translate").tag(WriteIntent.translate)
                Text("Dictionary").tag(WriteIntent.dictionary)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            if viewModel.intent == .refine {
                ForEach(RefineMode.allCases) { mode in
                    Button {
                        viewModel.selectMode(mode, modelContext: modelContext)
                    } label: {
                        Image(systemName: mode.symbol)
                            .help(mode.label)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(viewModel.selectedRefineMode == mode ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            } else if viewModel.intent == .translate {
                translateLanguagePickers
            }

            Spacer()

            if viewModel.isStreaming {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var translateLanguagePickers: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { viewModel.sourceOverride ?? "auto" },
                set: { viewModel.selectSource($0 == "auto" ? nil : $0, modelContext: modelContext) }
            )) {
                Text("Auto-detect").tag("auto")
                ForEach(LanguageOptions.codes, id: \.self) { code in
                    Text(LanguageDetector.displayName(for: code)).tag(code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { viewModel.targetOverride ?? "auto" },
                set: { viewModel.selectTarget($0 == "auto" ? nil : $0, modelContext: modelContext) }
            )) {
                Text("Auto").tag("auto")
                ForEach(LanguageOptions.codes, id: \.self) { code in
                    Text(LanguageDetector.displayName(for: code)).tag(code)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            originalSection
            resultSection
        }
        .padding(12)
    }

    @ViewBuilder
    private var originalSection: some View {
        if !viewModel.originalText.isEmpty, viewModel.intent != .dictionary {
            Text("Original")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(viewModel.originalText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 80)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let error = viewModel.errorMessage {
            errorSection(error)
        } else if case .dictionary(let entry) = viewModel.result {
            dictionarySection(entry: entry)
        } else {
            textResultSection
        }
    }

    private func dictionarySection(entry: DictionaryEntry) -> DictionaryEntryView {
        DictionaryEntryView(entry: entry, onAddToWordbook: wordbookHandler)
    }

    private var wordbookHandler: (@MainActor () async throws -> Void)? {
        guard viewModel.providerCanWriteWordbook else { return nil }
        return { [vm = viewModel] in try await vm.addToWordbook() }
    }

    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            if error.localizedCaseInsensitiveContains("accessibility") {
                Button("Open Privacy Settings") {
                    AccessibilityGuard.openSystemPrivacySettings()
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var textResultSection: some View {
        Text(resultLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
        ScrollView {
            Text(viewModel.result.streamingText.isEmpty ? "…" : viewModel.result.streamingText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minHeight: 60, maxHeight: 200)

        HStack(spacing: 8) {
            Spacer()
            let isPlaying = SpeechSynthesizer.shared.isPlaying(viewModel.result.asText)
            Button {
                SpeechSynthesizer.shared.toggle(viewModel.result.asText)
            } label: {
                Label(
                    isPlaying ? "Stop reading" : "Read aloud",
                    systemImage: isPlaying ? "speaker.fill" : "speaker.wave.2"
                )
                .labelStyle(.iconOnly)
            }
            .disabled(viewModel.result.isEmpty)
            .help(isPlaying ? "Stop reading" : "Read aloud")
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.result.asText, forType: .string)
            }
            .disabled(viewModel.result.isEmpty)
        }
    }

    private var resultLabel: LocalizedStringKey {
        switch viewModel.intent {
        case .refine: "Refined"
        case .translate: "Translation"
        case .dictionary: "Definition"
        }
    }
}

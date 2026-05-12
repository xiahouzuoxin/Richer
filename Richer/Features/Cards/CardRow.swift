import SwiftUI
import AppKit

struct CardRow: View {
    @Bindable var viewModel: CardViewModel
    var onTap: () -> Void
    var onRerun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.card.action.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 5))

                    Text(viewModel.headerLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    if viewModel.isStreaming {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(viewModel.isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if viewModel.isExpanded {
                Divider().opacity(0.5)
                expandedBody
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var expandedBody: some View {
        if viewModel.isProviderMissing {
            errorLabel(String(localized: "Provider missing — edit in Settings → Cards."))
        } else if let error = viewModel.errorMessage {
            errorLabel(error)
        } else if case .dictionary(let entry) = viewModel.result {
            dictionaryBody(entry: entry)
        } else {
            textBody
        }
    }

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let target = viewModel.resolvedTargetLanguage {
                Text("→ \(LanguageDetector.displayName(for: target))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                Text(viewModel.result.streamingText.isEmpty ? "…" : viewModel.result.streamingText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .font(.system(size: 13))
                    .transaction { $0.animation = nil }
            }
            .frame(minHeight: 40, maxHeight: 200)

            HStack(spacing: 12) {
                Spacer()
                speakerButton(for: viewModel.result.asText)
                    .disabled(viewModel.result.isEmpty)
                iconButton(systemName: "arrow.clockwise", help: "Re-run", action: onRerun)
                    .disabled(viewModel.isStreaming)
                iconButton(systemName: "doc.on.doc", help: "Copy result") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.result.asText, forType: .string)
                }
                .disabled(viewModel.result.isEmpty)
            }
        }
    }

    private var wordbookHandler: (@MainActor () async throws -> Void)? {
        guard viewModel.providerCanWriteWordbook else { return nil }
        return { [vm = viewModel] in try await vm.addToWordbook() }
    }

    private func dictionaryBody(entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DictionaryEntryView(entry: entry, onAddToWordbook: wordbookHandler)

            HStack(spacing: 12) {
                Spacer()
                speakerButton(for: entry.plainTextSummary)
                iconButton(systemName: "arrow.clockwise", help: "Re-run", action: onRerun)
                    .disabled(viewModel.isStreaming)
                iconButton(systemName: "doc.on.doc", help: "Copy summary") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.plainTextSummary, forType: .string)
                }
            }
        }
    }

    @ViewBuilder
    private func speakerButton(for text: String) -> some View {
        let isPlaying = SpeechSynthesizer.shared.isPlaying(text)
        iconButton(
            systemName: isPlaying ? "speaker.fill" : "speaker.wave.2",
            help: isPlaying ? "Stop reading" : "Read aloud"
        ) {
            SpeechSynthesizer.shared.toggle(text)
        }
        .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func iconButton(systemName: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

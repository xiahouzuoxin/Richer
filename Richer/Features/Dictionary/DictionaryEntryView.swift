import SwiftUI

struct DictionaryEntryView: View {
    let entry: DictionaryEntry
    /// When non-nil, the "Add to 生词本" button is shown and calls this on tap.
    /// The closure is async-throwing so callers can drive their own progress state.
    var onAddToWordbook: (@MainActor () async throws -> Void)?

    @State private var addState: AddState = .idle

    enum AddState: Equatable {
        case idle
        case adding
        case added
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !entry.phonetics.isEmpty {
                phoneticsRow
            }

            if !entry.senses.isEmpty {
                Divider().opacity(0.5)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(entry.senses.enumerated()), id: \.offset) { idx, sense in
                            senseBlock(index: idx + 1, sense: sense)
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: 220)
            }

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.word)
                .font(.system(size: 16, weight: .semibold))
                .textSelection(.enabled)
            speakerButton
            Spacer()
        }
    }

    @ViewBuilder
    private var speakerButton: some View {
        let isPlaying = SpeechSynthesizer.shared.isPlaying(entry.word)
        Button {
            SpeechSynthesizer.shared.toggle(entry.word)
        } label: {
            Image(systemName: isPlaying ? "speaker.fill" : "speaker.wave.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isPlaying ? "Stop reading" : "Read aloud")
    }

    private var phoneticsRow: some View {
        HStack(spacing: 12) {
            ForEach(Array(entry.phonetics.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 4) {
                    if p.region != .generic {
                        Text(p.region.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 3))
                    }
                    Text(p.ipa)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Sense block

    @ViewBuilder
    private func senseBlock(index: Int, sense: DictionaryEntry.Sense) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index).")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                if let pos = sense.partOfSpeech {
                    Text(pos)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 3))
                }
                Text(sense.definition)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(sense.examples.enumerated()), id: \.offset) { _, example in
                Text(example)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let onAddToWordbook {
                wordbookButton(onAddToWordbook: onAddToWordbook)
            }
            Spacer()
            Text(sourceLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var sourceLine: String {
        String(localized: "via \(entry.sourceLabel)")
    }

    @ViewBuilder
    private func wordbookButton(onAddToWordbook: @escaping @MainActor () async throws -> Void) -> some View {
        switch addState {
        case .idle:
            Button {
                Task {
                    addState = .adding
                    do {
                        try await onAddToWordbook()
                        addState = .added
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if addState == .added { addState = .idle }
                    } catch {
                        addState = .failed(error.localizedDescription)
                    }
                }
            } label: {
                Label("Add to wordbook", systemImage: "bookmark")
                    .font(.caption)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        case .adding:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Adding…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .added:
            Label("Added", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }
}

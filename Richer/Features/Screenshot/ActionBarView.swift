import SwiftUI

struct ActionBarView: View {
    let recognizedText: String
    var onAction: (Action) -> Void

    enum Action {
        case refine, translate, dictionary, copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            previewLine
            Divider().opacity(0.6)
            HStack(spacing: 8) {
                actionButton(.refine, label: "Refine", systemImage: "wand.and.stars")
                actionButton(.translate, label: "Translate", systemImage: "globe")
                actionButton(.dictionary, label: "Dictionary", systemImage: "book")
                actionButton(.copy, label: "Copy", systemImage: "doc.on.doc")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(radius: 6, y: 2)
    }

    private var previewLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 11))
                .foregroundStyle(.tint)
            Text(recognizedText)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(_ action: Action, label: LocalizedStringKey, systemImage: String) -> some View {
        Button {
            onAction(action)
        } label: {
            Label(label, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(minWidth: 60)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

import SwiftUI
import SwiftData
import AppKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Coordinator.self) private var coordinator
    @State private var query = ""
    @Query(sort: \HistoryEntry.timestamp, order: .reverse) private var allEntries: [HistoryEntry]

    private var filtered: [HistoryEntry] {
        guard !query.isEmpty else { return allEntries }
        return allEntries.filter {
            $0.originalText.localizedCaseInsensitiveContains(query) ||
            $0.resultText.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search history…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.thinMaterial)

            List {
                ForEach(filtered) { entry in
                    HistoryRow(entry: entry)
                        .contextMenu {
                            Button("Re-run") { coordinator.rerun(entry: entry) }
                            Button("Copy result") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.resultText, forType: .string)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                modelContext.delete(entry)
                                try? modelContext.save()
                            }
                        }
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: kindSymbol)
                    .foregroundStyle(.tint)
                Text(kindLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.originalText)
                .lineLimit(2)
                .foregroundStyle(.secondary)
            Text(entry.resultText)
                .lineLimit(3)
        }
        .padding(.vertical, 4)
    }

    private var kindSymbol: String {
        switch entry.kind {
        case .refine: "wand.and.stars"
        case .translate: "globe"
        case .dictionary: "book"
        }
    }

    private var kindLabel: String {
        switch entry.kind {
        case .refine: String(localized: "Refine • \(entry.modeOrTargetLang)")
        case .translate: String(localized: "Translate → \(entry.modeOrTargetLang)")
        case .dictionary: String(localized: "Dictionary • \(entry.modeOrTargetLang)")
        }
    }
}

@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?

    func show(coordinator: Coordinator, modelContainer: ModelContainer) {
        NSLog("[Richer] HistoryWindowController.show entered")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }

        let view = HistoryView()
            .environment(coordinator)
            .modelContainer(modelContainer)

        let hosting = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: hosting)
        w.title = "Richer History"
        w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        w.setContentSize(NSSize(width: 700, height: 500))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
    }
}

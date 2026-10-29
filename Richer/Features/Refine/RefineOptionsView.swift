import SwiftUI

/// Shared by the popup, input cards and card settings.
struct RefineOptionsView: View {
    @Binding var options: RefineOptions
    var compact = false
    @State private var showAdjustments = false

    private var tonePicker: some View {
        Picker("Tone", selection: $options.tone) {
            ForEach(RefineTone.allCases) { Text($0.label).tag($0) }
        }
    }

    private var lengthPicker: some View {
        Picker("Length", selection: $options.length) {
            ForEach(RefineLength.allCases) { Text($0.label).tag($0) }
        }
    }

    private var adjustmentPickers: some View {
        ViewThatFits(in: .horizontal) {
            HStack { tonePicker; lengthPicker }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading) { tonePicker; lengthPicker }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if compact {
                HStack {
                    Label(options.label, systemImage: "sparkles")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showAdjustments.toggle() } label: {
                        Label("Adjust", systemImage: "slider.horizontal.3")
                    }
                    .help(String(localized: "Adjust tone and length"))
                    .accessibilityLabel("Adjust tone and length")
                    .popover(isPresented: $showAdjustments, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Adjust tone and length").font(.headline)
                            tonePicker
                            lengthPicker
                        }
                        .padding(16)
                        .frame(width: 300)
                    }
                }
            }
            if !compact {
                adjustmentPickers
            }
        }
    }
}

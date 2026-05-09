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
            Image(systemName: viewModel.intent == .refine ? "wand.and.stars" : "globe")
                .foregroundStyle(.tint)
            Text(viewModel.intent == .refine ? "Richer • Refine" : "Richer • Translate")
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

    private var actionBar: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { viewModel.intent },
                set: { newValue in viewModel.switchTo(newValue, modelContext: modelContext) }
            )) {
                Text("Refine").tag(WriteIntent.refine)
                Text("Translate").tag(WriteIntent.translate)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

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
                targetButton(label: "Auto (en ↔ zh)", code: nil)
                targetButton(label: "→ EN", code: "en")
                targetButton(label: "→ ZH", code: "zh")
            }

            Spacer()

            if viewModel.isStreaming {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func targetButton(label: LocalizedStringKey, code: String?) -> some View {
        let isActive = (viewModel.targetOverride == code) || (code == nil && viewModel.targetOverride == nil)
        Button {
            viewModel.selectTarget(code, modelContext: modelContext)
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.originalText.isEmpty {
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

            if let error = viewModel.errorMessage {
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
            } else {
                Text(viewModel.intent == .refine ? "Refined" : "Translation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(viewModel.resultText.isEmpty ? "…" : viewModel.resultText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 60, maxHeight: 200)

                HStack {
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.resultText, forType: .string)
                    }
                    .disabled(viewModel.resultText.isEmpty)
                }
            }
        }
        .padding(12)
    }
}

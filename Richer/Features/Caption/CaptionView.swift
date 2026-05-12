import SwiftUI

struct CaptionView: View {
    @Bindable var viewModel: CaptionViewModel
    var onCopy: () -> Void
    var onSendToInput: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            micControl
            languageDeviceMenu
            Divider().frame(height: 18).opacity(0.4)
            captionText
            Divider().frame(height: 18).opacity(0.4)
            iconButton(systemName: "doc.on.doc", help: "Copy", action: onCopy)
                .disabled(viewModel.displayText.isEmpty)
            iconButton(systemName: "arrow.up.right.square", help: "Send to input window", action: onSendToInput)
                .disabled(viewModel.displayText.isEmpty)
            iconButton(systemName: "xmark", help: "Close", action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: 760)
        // Translucent dark bar (YouTube-caption style) — lets the underlying app
        // show through while keeping the text comfortably readable via the shadow.
        .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(radius: 12, y: 3)
        .colorScheme(.dark) // forces controls/icons to render in their dark-mode tint
    }

    // MARK: - Mic toggle

    private var micControl: some View {
        Button {
            viewModel.toggleMic()
        } label: {
            Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(viewModel.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(viewModel.isRecording ? "Stop dictating" : "Dictate")
    }

    // MARK: - Language + microphone chooser (reuses STTLocaleOption from InputView)

    private var languageDeviceMenu: some View {
        Menu {
            Section("Language") {
                ForEach(STTLocaleOption.allCases) { option in
                    Button {
                        viewModel.sttLocale = option.code
                    } label: {
                        if viewModel.sttLocale == option.code {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
            Section("Microphone") {
                Button {
                    viewModel.sttDeviceUID = nil
                } label: {
                    if viewModel.sttDeviceUID == nil {
                        Label("System default", systemImage: "checkmark")
                    } else {
                        Text("System default")
                    }
                }
                ForEach(AudioDeviceList.availableMicrophones()) { device in
                    Button {
                        viewModel.sttDeviceUID = device.uniqueID
                    } label: {
                        if viewModel.sttDeviceUID == device.uniqueID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 22)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(viewModel.isRecording)
        .help("Dictation language & microphone")
    }

    // MARK: - Caption text

    /// Caption font size — also drives the bar's overall height because the layout
    /// reserves three lines of this font no matter what.
    private let captionFontSize: CGFloat = 17
    /// Reserved minimum height for the caption area: 3 lines × line height + a touch
    /// of headroom. Without this, the bar visibly grows from 1-line to 3-line as text
    /// wraps in, which is distracting.
    private var captionMinHeight: CGFloat { captionFontSize * 1.35 * 3 + 4 }

    @ViewBuilder
    private var captionText: some View {
        if let err = viewModel.errorMessage {
            Text(err)
                .font(.system(size: captionFontSize - 4))
                .foregroundStyle(.orange)
                .lineLimit(3)
                .truncationMode(.tail)
                .help(err)
                .frame(maxWidth: .infinity, minHeight: captionMinHeight, alignment: .bottomLeading)
        } else if viewModel.displayText.isEmpty {
            Text(viewModel.isRecording ? "Listening…" : "Click the mic to start.")
                .font(.system(size: captionFontSize - 3))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, minHeight: captionMinHeight, alignment: .bottomLeading)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    // VStack with a leading Spacer + bottom alignment keeps short
                    // captions pinned at the bottom of the viewport (subtitle style);
                    // longer captions overflow upward and ScrollView reveals the tail.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Text(viewModel.displayText)
                            .font(.system(size: captionFontSize, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.75), radius: 1.5, x: 0, y: 1)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("captionTail")
                    }
                    .frame(minHeight: captionMinHeight, alignment: .bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: captionMinHeight)
                .onAppear {
                    proxy.scrollTo("captionTail", anchor: .bottom)
                }
                .onChange(of: viewModel.displayText) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("captionTail", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

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

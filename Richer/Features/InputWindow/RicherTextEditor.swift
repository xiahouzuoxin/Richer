import SwiftUI
import AppKit

/// Multi-line text editor that:
/// - Becomes first responder on appear (auto-focus).
/// - Treats plain Enter as "submit" (calls `onSubmit`).
/// - Treats Shift+Enter as a newline insertion.
struct RicherTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = text

        context.coordinator.textView = textView

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RicherTextEditor
        weak var textView: NSTextView?

        init(_ parent: RicherTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                if shiftPressed {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }
    }
}

/// Placeholder overlay for `RicherTextEditor`, since NSTextView has no built-in placeholder.
struct PlaceholderOverlay: View {
    let text: String
    let isVisible: Bool

    var body: some View {
        if isVisible {
            Text(text)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
        }
    }
}

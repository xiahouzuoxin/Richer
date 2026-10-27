// Offline AppKit regressions. Compile with InputPanel.swift and RicherTextEditor.swift.
import AppKit
import SwiftUI

@main struct InputMethodTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let panel = InputPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380))
        precondition(panel.styleMask.contains(.nonactivatingPanel))
        precondition(panel.level == .floating)
        precondition(panel.level.rawValue < NSWindow.Level.popUpMenu.rawValue)
        precondition(panel.canBecomeKey)
        precondition(panel.collectionBehavior.contains(.canJoinAllApplications))
        precondition(panel.collectionBehavior.contains(.fullScreenAuxiliary))

        var submitted = 0
        let editor = RicherTextEditor(text: .constant(""), placeholder: "", onSubmit: { submitted += 1 })
        let delegate = RicherTextEditor.Coordinator(editor)
        let scrollView = RicherInputTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? RicherInputTextView else {
            fatalError("The editor factory must create the IME-aware subclass")
        }
        panel.contentView = scrollView
        precondition(textView.needsPanelToBecomeKey)
        precondition(textView.windowLevel() == panel.level.rawValue)
        panel.level = .modalPanel
        precondition(textView.windowLevel() == NSWindow.Level.modalPanel.rawValue)
        panel.level = .floating
        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(textView.hasMarkedText())
        let handledDuringComposition = delegate.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        precondition(!handledDuringComposition && submitted == 0)
        textView.unmarkText()
        let handledAfterComposition = delegate.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        precondition(handledAfterComposition && submitted == 1)
        print("PASS: full-screen overlay configuration, live IME window level, composition and Return handling")
    }
}

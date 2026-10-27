import AppKit

final class InputPanel: NSPanel {
    // A nonactivating panel can take keyboard focus over another app, including
    // its full-screen Space. Keep it below the IME's candidate-window levels.
    static let presentationLevel: NSWindow.Level = .floating

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.titleVisibility = .visible
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.level = Self.presentationLevel
        self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
    }

    func presentForTextInput() {
        level = Self.presentationLevel
        deminiaturize(nil)
        // Remain in the caller's full-screen Space. Activating a regular app here
        // can put its IME in a different app/Space from this nonactivating panel.
        orderFrontRegardless()
        makeKey()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

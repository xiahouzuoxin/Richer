import AppKit

final class PopupPanel: NSPanel {
    private let _canBecomeKey: Bool

    init(contentRect: NSRect, canBecomeKey: Bool) {
        self._canBecomeKey = canBecomeKey
        let mask: NSWindow.StyleMask = canBecomeKey
            ? [.titled, .closable, .fullSizeContentView, .resizable, .nonactivatingPanel]
            : [.borderless, .nonactivatingPanel, .hudWindow]
        super.init(
            contentRect: contentRect,
            styleMask: mask,
            backing: .buffered,
            defer: false
        )
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { _canBecomeKey }
    override var canBecomeMain: Bool { false }
}

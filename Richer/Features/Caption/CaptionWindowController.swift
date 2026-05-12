import AppKit
import SwiftUI

@MainActor
final class CaptionWindowController {
    private var panel: CaptionPanel?
    private var viewModel: CaptionViewModel?
    private var keyMonitor: Any?

    /// Toggle: if the bar is already up, close it. Otherwise show.
    func show(coordinator: Coordinator) {
        if panel != nil {
            close()
            return
        }
        let vm = CaptionViewModel()
        self.viewModel = vm

        let view = CaptionView(
            viewModel: vm,
            onCopy: { [weak self] in
                guard let text = self?.viewModel?.displayText, !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            onSendToInput: { [weak coordinator, weak self] in
                guard let text = self?.viewModel?.displayText, !text.isEmpty else { return }
                self?.close()
                coordinator?.openInputWindow(intent: .refine, prefilledText: text)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Fixed size, sized for the worst case (three lines of 17pt caption text plus
        // 14pt vertical padding on each side). The view reserves the same minimum
        // height so the bar stays a constant size even when only one line of text
        // has been transcribed.
        let panelRect = NSRect(x: 0, y: 0, width: 760, height: 110)
        let panel = CaptionPanel(contentRect: panelRect)

        let container = NSView(frame: panelRect)
        container.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container

        // Position: bottom-center of the screen the cursor is currently on, with a
        // generous bottom margin so it doesn't collide with the Dock.
        let origin = bottomCenter(for: panel.frame.size)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        self.panel = panel
        installKeyMonitor()
    }

    func close() {
        viewModel?.tearDown()
        viewModel = nil
        removeKeyMonitor()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Internal

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in self?.close() }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func bottomCenter(for size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            return NSPoint(x: 100, y: 100)
        }
        let x = visible.minX + (visible.width - size.width) / 2
        let y = visible.minY + 80   // sit above the Dock
        return NSPoint(x: x, y: y)
    }
}

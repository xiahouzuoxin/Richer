import AppKit

/// Drives the region-picker UX across all connected displays. Returns the chosen rect
/// in global AppKit coordinates (origin bottom-left of primary screen) or nil if the
/// user cancelled (Esc, or click without dragging).
@MainActor
final class ScreenshotRegionController {
    private var panels: [(panel: ScreenshotRegionPanel, screen: NSScreen, view: RegionPickerView)] = []
    private var keyMonitor: Any?
    private var pushedCursor = false
    private var continuation: CheckedContinuation<NSRect?, Never>?

    func pickRegion() async -> NSRect? {
        // If a pick is somehow already in flight, abort it cleanly first.
        if continuation != nil {
            cleanup(result: nil)
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<NSRect?, Never>) in
            self.continuation = cont
            installPanels()
            installKeyMonitor()
        }
    }

    // MARK: - Setup

    private func installPanels() {
        for screen in NSScreen.screens {
            let view = RegionPickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.onComplete = { [weak self, weak view] rect in
                guard let self, let view else { return }
                self.handleComplete(view: view, rectInView: rect)
            }
            view.onCancel = { [weak self] in
                self?.cleanup(result: nil)
            }

            let panel = ScreenshotRegionPanel(screen: screen)
            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
            panel.makeKey()

            panels.append((panel, screen, view))
        }
        NSCursor.crosshair.push()
        pushedCursor = true
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 = Escape
            if event.keyCode == 53 {
                Task { @MainActor in self?.cleanup(result: nil) }
                return nil
            }
            return event
        }
    }

    // MARK: - Completion

    private func handleComplete(view: RegionPickerView, rectInView: NSRect) {
        guard let entry = panels.first(where: { $0.view === view }) else {
            cleanup(result: nil)
            return
        }
        let screen = entry.screen
        // Convert the in-view rect (view origin = screen origin) to global AppKit coords.
        let global = NSRect(
            x: screen.frame.origin.x + rectInView.origin.x,
            y: screen.frame.origin.y + rectInView.origin.y,
            width: rectInView.width,
            height: rectInView.height
        )
        cleanup(result: global)
    }

    private func cleanup(result: NSRect?) {
        for entry in panels { entry.panel.orderOut(nil) }
        panels.removeAll()
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: result)
        }
    }
}

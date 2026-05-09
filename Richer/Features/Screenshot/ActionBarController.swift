import AppKit
import SwiftUI

/// Shows the post-OCR action bar near the captured rect, dispatches button taps to
/// the caller, and tears itself down on outside click / Esc / button activation.
@MainActor
final class ActionBarController {
    private var panel: ActionBarPanel?
    private var globalMonitor: Any?
    private var keyMonitor: Any?

    /// Show the action bar. `nearRect` is in global AppKit coordinates (the same
    /// rect produced by `ScreenshotRegionController.pickRegion`). `onAction` is
    /// invoked once when the user picks a button (or never, if dismissed).
    func show(text: String, nearRect: NSRect, onAction: @escaping (ActionBarView.Action) -> Void) {
        dismiss()

        let view = ActionBarView(recognizedText: text) { [weak self] action in
            guard let self else { return }
            // Capture and tear down before invoking, so the popup the action opens
            // doesn't race with the action bar's monitors.
            self.dismiss()
            onAction(action)
        }
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Size: SwiftUI provides intrinsic sizing; cap width and let height auto-fit.
        let intrinsic = hosting.fittingSize
        let width = min(max(intrinsic.width, 360), 520)
        let height = max(intrinsic.height, 70)
        let panelRect = NSRect(x: 0, y: 0, width: width, height: height)
        let panel = ActionBarPanel(contentRect: panelRect)

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

        let origin = clamp(origin: NSPoint(x: nearRect.midX - width / 2, y: nearRect.minY - height - 8),
                           panelSize: panelRect.size)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        self.panel = panel
        installMonitors()
    }

    func dismiss() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Monitors

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                Task { @MainActor in self?.dismiss() }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        [globalMonitor, keyMonitor].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        globalMonitor = nil
        keyMonitor = nil
    }

    // MARK: - Positioning

    private func clamp(origin: NSPoint, panelSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main else {
            return origin
        }
        let visible = screen.visibleFrame
        var x = origin.x
        var y = origin.y
        if x + panelSize.width > visible.maxX { x = visible.maxX - panelSize.width - 10 }
        if x < visible.minX { x = visible.minX + 10 }
        if y < visible.minY { y = visible.minY + 10 }
        if y + panelSize.height > visible.maxY { y = visible.maxY - panelSize.height - 10 }
        return NSPoint(x: x, y: y)
    }
}

import AppKit
import SwiftData
import SwiftUI

@MainActor
final class PopupWindowController {
    private var panel: PopupPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var keyMonitor: Any?

    func show(viewModel: PopupViewModel, at point: NSPoint, modelContainer: ModelContainer) {
        NSLog("[Richer] PopupWindowController.show entered")
        dismiss()

        let view = PopupView(viewModel: viewModel) { [weak self] in
            Task { @MainActor in self?.dismiss() }
        }
        .modelContainer(modelContainer)

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panelRect = NSRect(x: 0, y: 0, width: 460, height: 360)
        let panel = PopupPanel(contentRect: panelRect, canBecomeKey: true)

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

        let placed = clamp(origin: point, panel: panel)
        panel.setFrameOrigin(placed)
        panel.orderFrontRegardless()

        self.panel = panel
        installMonitors()
        NSLog("[Richer] popup panel shown at \(panel.frame)")
    }

    func dismiss() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.dismiss() }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        [localMonitor, globalMonitor, keyMonitor].forEach { if let m = $0 { NSEvent.removeMonitor(m) } }
        localMonitor = nil; globalMonitor = nil; keyMonitor = nil
    }

    private func clamp(origin: NSPoint, panel: NSPanel) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main else {
            return origin
        }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        var x = origin.x
        var y = origin.y - size.height
        if x + size.width > visible.maxX { x = visible.maxX - size.width - 10 }
        if y < visible.minY { y = origin.y + 20 }
        if y + size.height > visible.maxY { y = visible.maxY - size.height - 10 }
        if x < visible.minX { x = visible.minX + 10 }
        return NSPoint(x: x, y: y)
    }
}

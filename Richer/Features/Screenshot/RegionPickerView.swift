import AppKit

/// NSView that paints a dimmed overlay everywhere except the live drag rectangle,
/// and reports the final rect (in view-local coordinates) via callbacks.
final class RegionPickerView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
        }
        guard let s = startPoint, let c = currentPoint else { return }
        let rect = normalizedRect(from: s, to: c)
        // Treat a near-zero rect (a click without dragging) as a cancel.
        if rect.width < 8 || rect.height < 8 {
            onCancel?()
        } else {
            onComplete?(rect)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.35)

        guard let s = startPoint, let c = currentPoint else {
            // No selection yet — uniform dim across the whole view.
            dim.setFill()
            bounds.fill()
            return
        }

        let selection = normalizedRect(from: s, to: c)

        // Even-odd path: outer rect (whole view) + inner rect (selection) cancel out
        // inside the selection, leaving a transparent hole.
        let path = NSBezierPath()
        path.append(NSBezierPath(rect: bounds))
        path.append(NSBezierPath(rect: selection))
        path.windingRule = .evenOdd
        dim.setFill()
        path.fill()

        // Accent border around the selection.
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()
    }

    private func normalizedRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}

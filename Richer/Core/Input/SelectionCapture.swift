import AppKit
import Carbon.HIToolbox

enum SelectionCaptureError: LocalizedError {
    case noSelection
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .noSelection: "No text selection found in the focused app."
        case .accessibilityDenied: "Accessibility permission is required to capture selection."
        }
    }
}

@MainActor
final class SelectionCapture {
    private let pollIntervalNs: UInt64 = 10_000_000   // 10 ms
    private let timeoutMs: Int = 500

    func captureSelection() async throws -> String {
        guard AccessibilityGuard.isTrusted else { throw SelectionCaptureError.accessibilityDenied }

        let pasteboard = NSPasteboard.general
        let savedItems = snapshot(pasteboard)
        let initialChange = pasteboard.changeCount

        postCommandC()

        let elapsedLimit = timeoutMs * 1_000_000
        var elapsed = 0
        var capturedString: String? = nil
        while elapsed < elapsedLimit {
            try await Task.sleep(nanoseconds: pollIntervalNs)
            elapsed += Int(pollIntervalNs)
            if pasteboard.changeCount != initialChange {
                capturedString = pasteboard.string(forType: .string)
                break
            }
        }

        restore(pasteboard, items: savedItems)

        if let text = capturedString, !text.isEmpty {
            return text
        }

        if let axText = AXFallback.readSelectedText(), !axText.isEmpty {
            return axText
        }

        throw SelectionCaptureError.noSelection
    }

    private func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restore(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        cDown?.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)

        let location = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: location)
        cDown?.post(tap: location)
        cUp?.post(tap: location)
        cmdUp?.post(tap: location)
    }
}

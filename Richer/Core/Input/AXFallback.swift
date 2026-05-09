import ApplicationServices
import AppKit

enum AXFallback {
    @MainActor
    static func readSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedRef = focused
        else { return nil }
        let element = focusedRef as! AXUIElement

        var selected: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
              let text = selected as? String
        else { return nil }
        return text
    }
}

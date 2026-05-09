import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let selectionRefine = Self("selectionRefine", default: .init(.r, modifiers: [.option, .shift]))
    static let selectionTranslate = Self("selectionTranslate", default: .init(.t, modifiers: [.option, .shift]))
    static let inputWindow = Self("inputWindow", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class HotkeyManager {
    func register(
        onSelectionRefine: @escaping @MainActor () -> Void,
        onSelectionTranslate: @escaping @MainActor () -> Void,
        onInputWindow: @escaping @MainActor () -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: .selectionRefine) { onSelectionRefine() }
        KeyboardShortcuts.onKeyDown(for: .selectionTranslate) { onSelectionTranslate() }
        KeyboardShortcuts.onKeyDown(for: .inputWindow) { onInputWindow() }
    }

    func unregister() {
        KeyboardShortcuts.removeAllHandlers()
    }
}

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let selectionRefine = Self("selectionRefine", default: .init(.r, modifiers: [.option, .shift]))
    static let selectionTranslate = Self("selectionTranslate", default: .init(.t, modifiers: [.option, .shift]))
    static let selectionDictionary = Self("selectionDictionary", default: .init(.d, modifiers: [.option, .shift]))
    static let inputWindow = Self("inputWindow", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class HotkeyManager {
    func register(
        onSelectionRefine: @escaping @MainActor () -> Void,
        onSelectionTranslate: @escaping @MainActor () -> Void,
        onSelectionDictionary: @escaping @MainActor () -> Void,
        onInputWindow: @escaping @MainActor () -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: .selectionRefine) { onSelectionRefine() }
        KeyboardShortcuts.onKeyDown(for: .selectionTranslate) { onSelectionTranslate() }
        KeyboardShortcuts.onKeyDown(for: .selectionDictionary) { onSelectionDictionary() }
        KeyboardShortcuts.onKeyDown(for: .inputWindow) { onInputWindow() }
    }

    func unregister() {
        KeyboardShortcuts.removeAllHandlers()
    }
}

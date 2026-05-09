import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = Coordinator()
    let modelContainer: ModelContainer = {
        let schema = Schema([HistoryEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    private let servicesHandler = ServicesHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = servicesHandler
        servicesHandler.coordinator = coordinator
        NSUpdateDynamicServices()

        coordinator.modelContainer = modelContainer
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}

final class ServicesHandler: NSObject {
    weak var coordinator: Coordinator?

    @objc func refineService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text selected" as NSString
            return
        }
        Task { @MainActor in
            self.coordinator?.openPopup(with: text, intent: .refine)
        }
    }

    @objc func translateService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text selected" as NSString
            return
        }
        Task { @MainActor in
            self.coordinator?.openPopup(with: text, intent: .translate)
        }
    }
}


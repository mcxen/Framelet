import AppKit
import SwiftUI

@main
struct FrameletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup("Framelet") {
            EditorView(store: EditorStore(services: services))
                .frame(minWidth: 1050, minHeight: 680)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

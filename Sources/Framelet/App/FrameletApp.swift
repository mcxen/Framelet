import AppKit
import SwiftUI

@main
struct FrameletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: EditorStore
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue

    init() {
        let services = AppServices()
        _store = State(initialValue: EditorStore(services: services))
    }

    var body: some Scene {
        WindowGroup("Framelet") {
            EditorView(store: store)
                .frame(minWidth: 1050, minHeight: 680)
                .preferredColorScheme(selectedTheme.colorScheme)
                .environment(\.locale, selectedLanguage.locale)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
                .preferredColorScheme(selectedTheme.colorScheme)
                .environment(\.locale, selectedLanguage.locale)
        }
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appTheme) ?? .system
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .system
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

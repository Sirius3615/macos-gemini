import SwiftUI

/// Main entry point for GeminiContext — a menu-bar-only macOS utility.
/// Uses SwiftUI lifecycle with MenuBarExtra for the system tray presence.
@main
struct GeminiContextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("GeminiContext", systemImage: "sparkles") {
            MenuBarView()
                .environmentObject(appDelegate.permissionsManager)
                .environmentObject(appDelegate.shakeDetector)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(appDelegate.shakeDetector)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

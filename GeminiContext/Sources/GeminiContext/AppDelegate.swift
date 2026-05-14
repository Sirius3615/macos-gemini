import AppKit
import SwiftUI
import Combine

/// Central orchestrator for the app's lifecycle.
/// Manages permissions, shake detection, screen capture, and floating panel.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    let permissionsManager = PermissionsManager()
    let shakeDetector = ShakeDetector()
    let screenCaptureManager = ScreenCaptureManager()
    let floatingPanelManager = FloatingPanelManager()

    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check permissions on launch
        permissionsManager.checkAllPermissions()

        // Wire up the shake detection callback
        shakeDetector.onShakeDetected = { [weak self] cursorLocation in
            self?.handleShake(at: cursorLocation)
        }

        // Observe accessibility permission to start/stop monitoring dynamically
        permissionsManager.$isAccessibilityGranted
            .removeDuplicates()
            .sink { [weak self] isGranted in
                if isGranted {
                    self?.shakeDetector.startMonitoring()
                } else {
                    self?.shakeDetector.stopMonitoring()
                }
            }
            .store(in: &cancellables)
            
        // Global keyboard shortcut monitor (Cmd+Shift+Space = space keycode 49)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard SettingsManager.shared.isShortcutEnabled else { return }
            
            // Check for Cmd + Shift + Space
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] && event.keyCode == 49 {
                let currentPos = NSEvent.mouseLocation
                self?.handleShake(at: currentPos)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeDetector.stopMonitoring()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Called when a valid mouse shake is detected.
    /// Captures the screen and spawns the floating AI chat panel.
    private func handleShake(at point: NSPoint) {
        Task { @MainActor in
            do {
                let image = try await screenCaptureManager.captureCurrentDisplay()

                // Also get JPEG data for the Gemini API
                var jpegData: Data?
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData) {
                    jpegData = bitmap.representation(
                        using: .jpeg,
                        properties: [.compressionFactor: 0.7]
                    )
                }

                floatingPanelManager.showPanel(at: point, with: image, screenshotData: jpegData)
            } catch {
                print("[GeminiContext] Screen capture failed: \(error.localizedDescription)")
                // Show panel without screenshot on capture failure
                floatingPanelManager.showPanel(at: point, with: nil, screenshotData: nil)
            }
        }
    }

    /// Re-check permissions and start monitoring if newly granted.
    func refreshPermissionsAndStart() {
        permissionsManager.checkAllPermissions()
        if permissionsManager.isAccessibilityGranted && !shakeDetector.isMonitoring {
            shakeDetector.startMonitoring()
        }
    }
}

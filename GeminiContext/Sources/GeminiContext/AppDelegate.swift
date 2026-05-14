import AppKit
import SwiftUI
import Combine

/// Central orchestrator for the app's lifecycle.
/// Manages permissions, shake detection, screen capture, and floating panel.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    let permissionsManager = PermissionsManager()
    let shakeDetector = ShakeDetector()
    let screenCaptureManager = ScreenCaptureManager()
    let floatingPanelManager = FloatingPanelManager.shared

    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check permissions on launch
        permissionsManager.checkAllPermissions()

        // Wire up the shake detection callback
        shakeDetector.onShakeDetected = { [weak self] cursorLocation in
            self?.handleActivation(at: cursorLocation, expandImmediately: false)
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
        
        // Register the global keyboard shortcut monitor
        registerShortcutMonitor()
        
        // Re-register when shortcuts change
        let settings = SettingsManager.shared
        Publishers.CombineLatest4(
            settings.$isShortcutEnabled,
            settings.$pillShortcut,
            settings.$fullChatShortcut,
            settings.$isShortcutEnabled // dummy to satisfy CombineLatest4
        )
        .dropFirst() // skip initial value
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.registerShortcutMonitor()
        }
        .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeDetector.stopMonitoring()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    /// Registers/re-registers the global keyboard shortcut monitor for both pill and full chat shortcuts.
    private func registerShortcutMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard SettingsManager.shared.isShortcutEnabled else { return }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let pillShortcut = SettingsManager.shared.pillShortcut
            let fullChatShortcut = SettingsManager.shared.fullChatShortcut
            
            // Check pill shortcut
            if event.keyCode == pillShortcut.keyCode && flags == pillShortcut.modifierFlags {
                let currentPos = NSEvent.mouseLocation
                self?.handleActivation(at: currentPos, expandImmediately: false)
                return
            }
            
            // Check full chat shortcut
            if event.keyCode == fullChatShortcut.keyCode && flags == fullChatShortcut.modifierFlags {
                let currentPos = NSEvent.mouseLocation
                self?.handleActivation(at: currentPos, expandImmediately: true)
                return
            }
        }
    }

    /// Called when a valid mouse shake or keyboard shortcut is detected.
    /// Captures the screen and spawns the floating AI chat panel.
    private func handleActivation(at point: NSPoint, expandImmediately: Bool) {
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

                floatingPanelManager.showPanel(at: point, with: image, screenshotData: jpegData, expandImmediately: expandImmediately)
            } catch {
                print("[GeminiContext] Screen capture failed: \(error.localizedDescription)")
                // Show panel without screenshot on capture failure
                floatingPanelManager.showPanel(at: point, with: nil, screenshotData: nil, expandImmediately: expandImmediately)
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

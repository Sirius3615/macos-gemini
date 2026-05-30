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
    let activeWindowReader = ActiveWindowReader.shared

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
        
        // Register ESC monitors to stop the agent
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && AgentOverlayManager.shared.isVisible {
                NotificationCenter.default.post(name: NSNotification.Name("CancelAgentGeneration"), object: nil)
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && AgentOverlayManager.shared.isVisible {
                NotificationCenter.default.post(name: NSNotification.Name("CancelAgentGeneration"), object: nil)
                // don't consume it if we also want floating panel to close, or maybe consume?
                // we'll return event to let other ESC handlers run
            }
            return event
        }
        
        // Re-register when shortcuts change
        let settings = SettingsManager.shared
        Publishers.CombineLatest3(
            settings.$isShortcutEnabled,
            settings.$pillShortcut,
            settings.$fullChatShortcut
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
    
    /// Registers/re-registers the global keyboard shortcut monitor for pill and full chat shortcuts.
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
        // Read active window context BEFORE capturing (since capture may change focus)
        let activeContext = activeWindowReader.readActiveContext()
        
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

                if expandImmediately {
                    ChatWindowManager.shared.openRegularChatWindow(screenshot: image, screenshotData: jpegData, activeContext: activeContext)
                } else {
                    floatingPanelManager.showPanel(at: point, with: image, screenshotData: jpegData, expandImmediately: false, activeContext: activeContext)
                }
            } catch {
                print("[GeminiContext] Screen capture failed: \(error.localizedDescription)")
                if expandImmediately {
                    ChatWindowManager.shared.openRegularChatWindow(screenshot: nil, screenshotData: nil, activeContext: activeContext)
                } else {
                    floatingPanelManager.showPanel(at: point, with: nil, screenshotData: nil, expandImmediately: false, activeContext: activeContext)
                }
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

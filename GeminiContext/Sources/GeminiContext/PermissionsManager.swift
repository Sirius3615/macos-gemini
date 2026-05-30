import AppKit
import Combine
import EventKit

/// Manages checking and prompting for required system permissions:
/// - Accessibility (for global mouse event monitoring)
/// - Screen Recording (for ScreenCaptureKit)
final class PermissionsManager: ObservableObject {

    @Published var isAccessibilityGranted: Bool = false
    @Published var isScreenRecordingGranted: Bool = false
    @Published var isCalendarGranted: Bool = false

    private var timer: Timer?

    init() {
        startPolling()
    }

    /// Checks all required permissions and updates published state.
    func checkAllPermissions() {
        checkAccessibility(prompt: false)
        checkScreenRecording()
        checkCalendar()
    }

    /// Starts a timer to poll for permissions if they are not yet granted.
    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.checkAllPermissions()
            
            // Stop polling if all are granted
            if self.isAccessibilityGranted && self.isScreenRecordingGranted && self.isCalendarGranted {
                self.stopPolling()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Accessibility

    /// Checks if Accessibility permission is granted.
    /// On first call with `prompt: true`, shows the system dialog directing
    /// the user to System Settings > Privacy & Security > Accessibility.
    func checkAccessibility(prompt: Bool = false) {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt]
        let granted = AXIsProcessTrustedWithOptions(options)
        if isAccessibilityGranted != granted {
            isAccessibilityGranted = granted
        }
    }

    /// Opens System Settings to the Accessibility pane.
    func openAccessibilitySettings() {
        // Prompt via the trusted check (shows system alert)
        checkAccessibility(prompt: true)
        startPolling() // Ensure we are polling after they open settings
    }

    // MARK: - Screen Recording

    /// Checks Screen Recording permission by attempting to access shareable content.
    /// ScreenCaptureKit will throw if permission is not granted, which also
    /// triggers the system permission prompt on first attempt.
    func checkScreenRecording() {
        // Use CGWindowListCopyWindowInfo as a lightweight permission check.
        // If Screen Recording is not granted, this returns nil or an empty list
        // for windows belonging to other applications.
        if let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
            // If we can see windows from other apps, permission is granted
            let otherAppWindows = windowList.filter { dict in
                guard let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32 else { return false }
                return ownerPID != ProcessInfo.processInfo.processIdentifier
            }
            let granted = !otherAppWindows.isEmpty
            if isScreenRecordingGranted != granted {
                isScreenRecordingGranted = granted
            }
        } else {
            if isScreenRecordingGranted != false {
                isScreenRecordingGranted = false
            }
        }
    }

    /// Opens System Settings to the Screen Recording pane.
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        startPolling() // Ensure we are polling after they open settings
    }

    // MARK: - Calendar

    /// Checks if Calendar permission is granted.
    func checkCalendar() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = status == .fullAccess
        } else {
            granted = status == .authorized
        }
        if isCalendarGranted != granted {
            isCalendarGranted = granted
        }
    }

    /// Requests calendar access and starts polling for updates.
    func requestCalendarAccess() {
        Task {
            let granted = await CalendarService.shared.requestAccess()
            await MainActor.run {
                isCalendarGranted = granted
            }
        }
        startPolling()
    }

    /// Opens System Settings to the Calendar privacy pane.
    func openCalendarSettings() {
        // First attempt to request access (shows system dialog)
        requestCalendarAccess()
        // Also open the settings pane
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

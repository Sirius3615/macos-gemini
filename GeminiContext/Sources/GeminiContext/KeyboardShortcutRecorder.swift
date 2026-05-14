import SwiftUI
import Carbon.HIToolbox

/// A SwiftUI view that captures a keyboard shortcut combination.
/// Click to start recording, press a key combo, and it saves the shortcut.
struct KeyboardShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcutConfig
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var showModifierWarning = false
    
    var body: some View {
        Button(action: {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }) {
            HStack(spacing: 6) {
                if isRecording {
                    Text(showModifierWarning ? "Add a modifier (⌘, ⇧, ⌥, ⌃)" : "Press keys...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(showModifierWarning ? .red : .orange)
                } else {
                    Text(shortcut.displayString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 100, minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.orange.opacity(0.1) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? (showModifierWarning ? Color.red.opacity(0.5) : Color.orange.opacity(0.5)) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        // Clear any previous state
        stopRecording()
        isRecording = true
        showModifierWarning = false
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                // Just used to clear warning if they press a modifier
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if !flags.isEmpty {
                    DispatchQueue.main.async { self.showModifierWarning = false }
                }
                return event
            }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            // Escape cancels recording
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            
            // Require at least one modifier key (Cmd, Ctrl, Opt, or Shift)
            // Note: Shift + Alpha is usually not a good global shortcut, but we'll allow it.
            let hasModifier = flags.contains(.command) || 
                             flags.contains(.control) || 
                             flags.contains(.option) || 
                             flags.contains(.shift)
            
            if !hasModifier {
                // If it's a function key (F1-F12), we might want to allow it without modifiers,
                // but for global apps, it's safer to require one.
                // For now, just show a warning.
                DispatchQueue.main.async { self.showModifierWarning = true }
                return nil
            }
            
            // Success! Capture the shortcut.
            let newShortcut = KeyboardShortcutConfig(
                keyCode: event.keyCode,
                modifiers: flags.rawValue
            )
            
            DispatchQueue.main.async {
                self.shortcut = newShortcut
                self.stopRecording()
            }
            
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        showModifierWarning = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}


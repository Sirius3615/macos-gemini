import AppKit
import SwiftUI

/// Manages the lifecycle of the proper standalone regular chat window.
/// Promotes the expanded chat state to a native resizable macOS window.
@MainActor
final class ChatWindowManager: NSObject, ObservableObject {
    static let shared = ChatWindowManager()
    
    private var chatWindow: NSWindow?
    
    private override init() {
        super.init()
    }
    
    /// Dynamically updates the activation policy based on visible regular windows.
    func updateActivationPolicy() {
        let hasVisibleRegularWindows = NSApp.windows.contains { window in
            guard window.isVisible else { return false }
            let className = window.className
            if className.contains("Panel") || className.contains("StatusItem") || className.contains("Background") {
                return false
            }
            let title = window.title
            let identifier = window.identifier?.rawValue
            return title == "AI Chat" || title == "Settings" || identifier == "settings"
        }
        
        if hasVisibleRegularWindows {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
    
    /// Opens the regular chat window with the optional captured screenshot and active context.
    /// If the window is already open, it activates and brings it to the front.
    func openRegularChatWindow(
        screenshot: NSImage? = nil,
        screenshotData: Data? = nil,
        activeContext: ActiveWindowContext? = nil
    ) {
        if let window = chatWindow {
            updateActivationPolicy()
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.title = "AI Chat"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 500)
        window.center()
        window.delegate = self
        
        // Match the app's dark native aesthetic and prevent click-throughs
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0) // Deep Dark Base (#0D0D14)
        window.isOpaque = true
        window.hasShadow = true
        
        let chatView = ChatView(
            screenshot: screenshot,
            screenshotData: screenshotData,
            activeContext: activeContext,
            onDismiss: {
                ChatWindowManager.shared.closeRegularChatWindow()
            },
            onResize: { _ in
                // Standard windows resize natively via OS window manager
            },
            initiallyExpanded: true,
            isRegularWindow: true // Tell ChatView to hide its own close button
        )
        
        let hostingView = NSHostingView(rootView: chatView)
        window.contentView = hostingView
        self.chatWindow = window
        
        // Ensure regular activation policy for Dock integration and keyboard focus
        updateActivationPolicy()
        window.makeKeyAndOrderFront(nil)
        
        // Ensure keyboard focus reaches the text field
        window.makeFirstResponder(hostingView)
    }
    
    /// Closes the regular chat window.
    func closeRegularChatWindow() {
        chatWindow?.close()
        chatWindow = nil
    }
}

extension ChatWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        chatWindow = nil
        // Delay slightly to let the OS update window visibility state
        DispatchQueue.main.async {
            self.updateActivationPolicy()
        }
    }
}

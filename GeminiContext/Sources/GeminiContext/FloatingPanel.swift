import AppKit
import SwiftUI

/// A custom NSPanel subclass configured as a borderless, floating, translucent panel.
/// Designed to host SwiftUI content and sit above all other windows.
///
/// Key behaviors:
/// - Borderless with no title bar
/// - Floating window level (always on top)
/// - HUD-style frosted glass background via NSVisualEffectView
/// - Accepts keyboard input (canBecomeKey)
/// - Draggable by background
/// - Visible on all Spaces
final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )

        configurePanel(contentRect: contentRect)
    }

    private func configurePanel(contentRect: NSRect) {
        // Appearance
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Behavior
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        // Visibility across Spaces and Fullscreen
        collectionBehavior = [.fullScreenPrimary, .managed]

        // Animation
        animationBehavior = .utilityWindow
        
        // Add NSVisualEffectView as the background for native frosted glass
        let visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentRect.size))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.autoresizingMask = [.width, .height]
        contentView = visualEffectView
    }

    // MARK: - Overrides

    /// Allow the panel to become the key window so it can accept keyboard input
    /// (needed for the chat text field).
    override var canBecomeKey: Bool {
        return true
    }

    /// Allow the panel to become the main window.
    override var canBecomeMain: Bool {
        return false
    }
    
    /// Override contentView setter to nest inside the visual effect view.
    override var contentView: NSView? {
        get { return super.contentView }
        set {
            if let vev = super.contentView as? NSVisualEffectView, let newView = newValue, !(newValue is NSVisualEffectView) {
                // Add the new view as a subview of the visual effect view
                newView.frame = vev.bounds
                newView.autoresizingMask = [.width, .height]
                // Remove existing subviews except the new one
                vev.subviews.forEach { $0.removeFromSuperview() }
                vev.addSubview(newView)
            } else {
                super.contentView = newValue
            }
        }
    }
}

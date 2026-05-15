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
            // By default not resizable. The manager will add .resizable when expanded.
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
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
        
        // We do not add NSVisualEffectView here, because SwiftUI ChatView provides its own.
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
}

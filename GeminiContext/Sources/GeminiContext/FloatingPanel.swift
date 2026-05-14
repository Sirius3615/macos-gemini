import AppKit
import SwiftUI

/// A custom NSPanel subclass configured as a borderless, floating, translucent panel.
/// Designed to host SwiftUI content and sit above all other windows.
///
/// Key behaviors:
/// - Borderless with no title bar
/// - Floating window level (always on top)
/// - Transparent background (SwiftUI provides the visual chrome)
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

        configurePanel()
    }

    private func configurePanel() {
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

import AppKit
import ScreenCaptureKit
import SwiftUI

/// Manages screen capture using ScreenCaptureKit (macOS 14+).
/// Provides single-frame screenshot capture with automatic downsampling.
final class ScreenCaptureManager {

    /// Maximum width for captured screenshots (for memory efficiency).
    private let maxCaptureWidth: Int = 1920

    /// JPEG compression quality for the captured image.
    private let compressionQuality: CGFloat = 0.7

    // MARK: - Public API

    /// Captures the display where the cursor currently resides.
    /// Returns an NSImage suitable for display in the floating panel.
    ///
    /// - Throws: If ScreenCaptureKit fails (e.g., no permission).
    /// - Returns: An NSImage of the captured screen content, downsampled for efficiency.
    func captureCurrentDisplay() async throws -> NSImage {
        // 1. Get shareable content (this also triggers permission prompt if needed)
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        // 2. Find the display containing the cursor
        let cursorLocation = NSEvent.mouseLocation
        let targetDisplay = findDisplay(
            containing: cursorLocation,
            in: availableContent.displays
        ) ?? availableContent.displays.first

        guard let display = targetDisplay else {
            throw CaptureError.noDisplayFound
        }

        // 3. Create content filter (capture entire display, exclude our own windows)
        let ownWindows = availableContent.windows.filter { window in
            window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingWindows: ownWindows
        )

        // 4. Configure capture with downsampling
        let config = SCStreamConfiguration()
        let scale = min(1.0, CGFloat(maxCaptureWidth) / CGFloat(display.width))
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.scalesToFit = true

        // 5. Capture single frame
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // 6. Convert to NSImage
        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        return nsImage
    }

    /// Captures the current display and returns compressed JPEG data.
    /// Use this when you need to send the image to an AI API.
    func captureCurrentDisplayAsData() async throws -> Data {
        let image = try await captureCurrentDisplay()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: compressionQuality]
              ) else {
            throw CaptureError.compressionFailed
        }

        return jpegData
    }
    
    // MARK: - Region Capture
    
    /// Presents a fullscreen overlay for the user to select a screen region via click-and-drag.
    /// Returns the captured region as an NSImage.
    @MainActor
    func captureRegion() async throws -> NSImage {
        // Get the selected region from the overlay
        let selectedRect = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGRect, Error>) in
            let overlay = RegionSelectionOverlay { rect in
                if let rect = rect {
                    continuation.resume(returning: rect)
                } else {
                    continuation.resume(throwing: CaptureError.regionCancelled)
                }
            }
            overlay.show()
        }
        
        // Small delay to let the overlay dismiss before capturing
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Capture the full screen first
        let fullImage = try await captureCurrentDisplay()
        
        // Get the screen that contains the center of the selection
        let cursorLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorLocation) }) ?? NSScreen.main else {
            throw CaptureError.noDisplayFound
        }
        
        // Convert the screen-coordinate rect to image-coordinate rect
        let screenFrame = screen.frame
        let imageWidth = fullImage.size.width
        let imageHeight = fullImage.size.height
        let scaleX = imageWidth / screenFrame.width
        let scaleY = imageHeight / screenFrame.height
        
        // The selected rect is in screen coordinates (flipped from bottom-left)
        // Convert to image coordinates
        let imageRect = CGRect(
            x: (selectedRect.origin.x - screenFrame.origin.x) * scaleX,
            y: (screenFrame.height - selectedRect.origin.y - selectedRect.height - screenFrame.origin.y) * scaleY,
            width: selectedRect.width * scaleX,
            height: selectedRect.height * scaleY
        )
        
        // Crop the full image
        var proposedRect = NSRect(x: 0, y: 0, width: fullImage.size.width, height: fullImage.size.height)
        guard let cgImage = fullImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let croppedCG = cgImage.cropping(to: imageRect) else {
            throw CaptureError.compressionFailed
        }
        
        return NSImage(cgImage: croppedCG, size: NSSize(width: croppedCG.width, height: croppedCG.height))
    }

    // MARK: - Private Helpers

    /// Finds the SCDisplay that contains the given screen point.
    private func findDisplay(containing point: NSPoint, in displays: [SCDisplay]) -> SCDisplay? {
        // NSEvent.mouseLocation uses bottom-left origin coordinate system
        for display in displays {
            let frame = CGRect(
                x: Int(display.frame.origin.x),
                y: Int(display.frame.origin.y),
                width: display.width,
                height: display.height
            )
            if frame.contains(point) {
                return display
            }
        }
        return nil
    }
}

// MARK: - Region Selection Overlay

/// A fullscreen transparent NSWindow overlay for marquee region selection.
/// Shows a crosshair cursor and lets the user drag to select a rectangular region.
@MainActor
final class RegionSelectionOverlay: NSObject {
    private var overlayWindow: NSWindow?
    private let onComplete: (CGRect?) -> Void
    private var startPoint: NSPoint = .zero
    private var currentRect: CGRect = .zero
    private var selectionView: RegionSelectionView?
    
    init(onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init()
    }
    
    func show() {
        guard let screen = NSScreen.main else {
            onComplete(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces]
        
        let view = RegionSelectionView(frame: screen.frame) { [weak self] rect in
            self?.dismiss()
            self?.onComplete(rect)
        }
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        
        // Set crosshair cursor
        NSCursor.crosshair.push()
        
        self.overlayWindow = window
        self.selectionView = view
    }
    
    private func dismiss() {
        NSCursor.pop()
        overlayWindow?.orderOut(nil)
        overlayWindow?.close()
        overlayWindow = nil
    }
}

/// Custom NSView for handling mouse events during region selection.
final class RegionSelectionView: NSView {
    private let onComplete: (CGRect?) -> Void
    private var startPoint: NSPoint = .zero
    private var currentRect: CGRect = .zero
    private var isDragging = false
    
    init(frame: NSRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        isDragging = true
        currentRect = .zero
        setNeedsDisplay(bounds)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let current = event.locationInWindow
        let x = min(startPoint.x, current.x)
        let y = min(startPoint.y, current.y)
        let w = abs(startPoint.x - current.x)
        let h = abs(startPoint.y - current.y)
        currentRect = CGRect(x: x, y: y, width: w, height: h)
        setNeedsDisplay(bounds)
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if currentRect.width > 10 && currentRect.height > 10 {
            // Convert window coordinates to screen coordinates
            if let window = self.window {
                let screenRect = window.convertToScreen(currentRect)
                onComplete(screenRect)
            } else {
                onComplete(currentRect)
            }
        } else {
            onComplete(nil)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // ESC to cancel
        if event.keyCode == 53 {
            onComplete(nil)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Semi-transparent background
        NSColor.black.withAlphaComponent(0.2).setFill()
        dirtyRect.fill()
        
        if currentRect.width > 0 && currentRect.height > 0 {
            // Clear the selected region
            NSColor.clear.setFill()
            NSBezierPath(rect: currentRect).fill()
            
            // Draw selection border
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let borderPath = NSBezierPath(rect: currentRect)
            borderPath.lineWidth = 2
            borderPath.setLineDash([5, 3], count: 2, phase: 0)
            borderPath.stroke()
            
            // Draw size label
            let sizeText = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.6)
            ]
            let textSize = sizeText.size(withAttributes: attrs)
            let textPoint = NSPoint(
                x: currentRect.midX - textSize.width / 2,
                y: currentRect.maxY + 6
            )
            sizeText.draw(at: textPoint, withAttributes: attrs)
        }
        
        // Draw crosshair at mouse location
        let mouseLocation = window?.mouseLocationOutsideOfEventStream ?? .zero
        NSColor.white.withAlphaComponent(0.5).setStroke()
        let hLine = NSBezierPath()
        hLine.move(to: NSPoint(x: 0, y: mouseLocation.y))
        hLine.line(to: NSPoint(x: bounds.width, y: mouseLocation.y))
        hLine.lineWidth = 0.5
        hLine.stroke()
        
        let vLine = NSBezierPath()
        vLine.move(to: NSPoint(x: mouseLocation.x, y: 0))
        vLine.line(to: NSPoint(x: mouseLocation.x, y: bounds.height))
        vLine.lineWidth = 0.5
        vLine.stroke()
    }
    
    override func mouseMoved(with event: NSEvent) {
        setNeedsDisplay(bounds)
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplayFound
    case compressionFailed
    case regionCancelled

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found at cursor location."
        case .compressionFailed:
            return "Failed to compress captured image."
        case .regionCancelled:
            return "Region selection was cancelled."
        }
    }
}

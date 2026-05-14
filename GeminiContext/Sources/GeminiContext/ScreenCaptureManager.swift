import AppKit
import ScreenCaptureKit

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

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplayFound
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found at cursor location."
        case .compressionFailed:
            return "Failed to compress captured image."
        }
    }
}

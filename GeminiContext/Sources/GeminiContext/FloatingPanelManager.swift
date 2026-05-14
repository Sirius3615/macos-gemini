import AppKit
import SwiftUI

/// Manages the lifecycle of the floating AI chat panel.
/// Ensures only one panel exists at a time.
final class FloatingPanelManager: NSObject, ObservableObject {
    static let shared = FloatingPanelManager()
    
    @Published var isPinned = false {
        didSet {
            currentPanel?.level = isPinned ? .floating : .normal
        }
    }
    
    /// Guards against dismissal when NSOpenPanel or screenshot editor is open.
    @Published var isFilePickerOpen = false
    @Published var isScreenshotEditorOpen = false
    
    private var currentPanel: FloatingPanel?
    private var eventMonitor: Any?
    private let expandedSize = NSSize(width: 480, height: 580)
    private let pillSize = NSSize(width: 500, height: 56)

    private override init() {
        super.init()
    }

    @MainActor
    func showPanel(at point: NSPoint, with screenshot: NSImage?, screenshotData: Data? = nil, expandImmediately: Bool = false, activeContext: ActiveWindowContext? = nil) {
        dismissPanel(force: true)
        
        // Reset pin state on new invocation
        isPinned = false
        
        let initialSize = expandImmediately ? expandedSize : pillSize
        let startOrigin = calculatePanelOrigin(cursorPoint: point, size: initialSize)
        
        let panel = FloatingPanel(contentRect: NSRect(origin: startOrigin, size: initialSize))
        var chatView = ChatView(
            screenshot: screenshot,
            screenshotData: screenshotData,
            activeContext: activeContext,
            onDismiss: { [weak self] in
                self?.dismissPanel(force: true)
            },
            onResize: { [weak panel] newSize in
                guard let panel = panel else { return }
                var frame = panel.frame
                // Anchor top-left, meaning Y decreases
                frame.origin.y -= (newSize.height - frame.size.height)
                frame.size = newSize
                
                // Ensure the expanded panel doesn't go off the bottom of the screen
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(panel.frame) }) ?? NSScreen.main {
                    let vf = screen.visibleFrame
                    if frame.origin.y < vf.minY {
                        frame.origin.y = vf.minY + 16
                    }
                }
                
                panel.animator().setFrame(frame, display: true)
            }
        )
        chatView.initiallyExpanded = expandImmediately
        let hostingView = NSHostingView(rootView: chatView)
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.delegate = self
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        // Clean up old monitor
        if let monitors = eventMonitor as? [Any] {
            for monitor in monitors {
                NSEvent.removeMonitor(monitor)
            }
        } else if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitor = nil

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if self?.isPinned == false {
                    self?.dismissPanel()
                }
                return nil
            }
            return event
        }
        
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            // Don't dismiss when file picker or screenshot editor is open
            if self.isFilePickerOpen || self.isScreenshotEditorOpen { return }
            if self.isPinned == false {
                self.dismissPanel()
            }
        }
        
        // Store monitors as an array if needed, or create a struct. 
        // For simplicity, we can store them in an array in `eventMonitor` since it's `Any?`.
        eventMonitor = [localMonitor, globalMonitor]
        currentPanel = panel
    }

    @MainActor
    func dismissPanel(force: Bool = false) {
        if isPinned && !force { return }
        
        if let monitors = eventMonitor as? [Any] {
            for monitor in monitors {
                if let m = monitor as? Any { // Safely unwrap
                    NSEvent.removeMonitor(m)
                }
            }
            eventMonitor = nil
        } else if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        guard let panel = currentPanel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.close()
        })
        currentPanel = nil
    }

    private func calculatePanelOrigin(cursorPoint: NSPoint, size: NSSize) -> NSPoint {
        let offset: CGFloat = 16
        var x = cursorPoint.x + offset
        var y = cursorPoint.y - size.height - offset
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            if x + size.width > vf.maxX { x = cursorPoint.x - size.width - offset }
            if x < vf.minX { x = vf.minX + offset }
            if y < vf.minY { y = cursorPoint.y + offset }
            if y + size.height > vf.maxY { y = vf.maxY - size.height - offset }
        }
        return NSPoint(x: x, y: y)
    }
}

extension FloatingPanelManager: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(Double(window.frame.width), forKey: "panelWidth")
        UserDefaults.standard.set(Double(window.frame.height), forKey: "panelHeight")
    }
}

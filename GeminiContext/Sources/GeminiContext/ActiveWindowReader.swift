import AppKit
import ApplicationServices

/// Context gathered from the currently active window using Accessibility APIs.
struct ActiveWindowContext {
    let appName: String
    let bundleIdentifier: String
    let selectedText: String
    let activeURL: String
    
    var isEmpty: Bool {
        selectedText.isEmpty && activeURL.isEmpty
    }
    
    /// Produces a concise context string for inclusion in AI prompts.
    var contextDescription: String {
        var parts: [String] = []
        if !appName.isEmpty {
            parts.append("Active app: \(appName)")
        }
        if !activeURL.isEmpty {
            parts.append("Active URL: \(activeURL)")
        }
        if !selectedText.isEmpty {
            // Limit selected text to avoid huge prompts
            let trimmed = selectedText.prefix(2000)
            parts.append("Selected text:\n\(trimmed)")
        }
        return parts.joined(separator: "\n")
    }
}

/// Reads context from the frontmost application using macOS Accessibility APIs (AXUIElement).
/// Requires Accessibility permission to function.
final class ActiveWindowReader {
    
    static let shared = ActiveWindowReader()
    
    private init() {}
    
    /// Reads the active window context: app name, selected text, and active URL.
    /// Returns an empty context if accessibility is not granted or reading fails.
    func readActiveContext() -> ActiveWindowContext {
        let systemWide = AXUIElementCreateSystemWide()
        
        // Get the frontmost application
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        
        guard appResult == .success, let appElement = focusedApp else {
            return ActiveWindowContext(appName: "", bundleIdentifier: "", selectedText: "", activeURL: "")
        }
        
        let appName = getStringAttribute(appElement as! AXUIElement, attribute: kAXTitleAttribute)
        let bundleID = getFrontmostBundleIdentifier() ?? ""
        
        // Get selected text from the focused UI element
        let selectedText = getSelectedText(from: appElement as! AXUIElement)
        
        // Try to get the active URL (for browsers)
        let activeURL = getActiveURL(bundleID: bundleID, appElement: appElement as! AXUIElement)
        
        return ActiveWindowContext(
            appName: appName,
            bundleIdentifier: bundleID,
            selectedText: selectedText,
            activeURL: activeURL
        )
    }
    
    // MARK: - Private Helpers
    
    /// Gets the selected text from the focused element of the given application.
    private func getSelectedText(from appElement: AXUIElement) -> String {
        // First, get the focused UI element
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard result == .success, let element = focusedElement else {
            return ""
        }
        
        // Try to get the selected text attribute
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }
        
        return ""
    }
    
    /// Attempts to read the active URL from known browser apps via their AX hierarchy.
    private func getActiveURL(bundleID: String, appElement: AXUIElement) -> String {
        let browserBundleIDs = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.brave.Browser",
            "company.thebrowser.Browser", // Arc
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.operasoftware.Opera"
        ]
        
        guard browserBundleIDs.contains(where: { bundleID.contains($0) || $0.contains(bundleID) }) else {
            return ""
        }
        
        // Get the focused window
        var focusedWindow: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard windowResult == .success, let window = focusedWindow else {
            return ""
        }
        
        // For Safari, the URL is in the address bar (AXTextField with AXDescription "Address and Search")
        // For Chrome-based browsers, look for address bar with AXRoleDescription "address field"
        if let url = findURLInElement(window as! AXUIElement, depth: 0, maxDepth: 8) {
            return url
        }
        
        return ""
    }
    
    /// Recursively searches the AX element tree for a URL bar and reads its value.
    private func findURLInElement(_ element: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        guard depth < maxDepth else { return nil }
        
        // Check this element
        let role = getStringAttribute(element, attribute: kAXRoleAttribute)
        let roleDescription = getStringAttribute(element, attribute: kAXRoleDescriptionAttribute)
        let description = getStringAttribute(element, attribute: kAXDescriptionAttribute)
        
        // Safari: AXTextField with description containing "address" or "URL"
        // Chrome: AXTextField with roleDescription "address"
        let isAddressBar = (role == "AXTextField" || role == "AXComboBox") &&
            (description.localizedCaseInsensitiveContains("address") ||
             description.localizedCaseInsensitiveContains("url") ||
             roleDescription.localizedCaseInsensitiveContains("address"))
        
        if isAddressBar {
            let value = getStringAttribute(element, attribute: kAXValueAttribute)
            if !value.isEmpty {
                return value
            }
        }
        
        // Recurse into children
        var children: AnyObject?
        let childResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        
        guard childResult == .success, let childArray = children as? [AXUIElement] else {
            return nil
        }
        
        for child in childArray {
            if let url = findURLInElement(child, depth: depth + 1, maxDepth: maxDepth) {
                return url
            }
        }
        
        return nil
    }
    
    /// Reads a string attribute from an AXUIElement.
    private func getStringAttribute(_ element: AXUIElement, attribute: String) -> String {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .success, let str = value as? String {
            return str
        }
        return ""
    }
    
    /// Gets the bundle identifier of the frontmost application via NSWorkspace.
    private func getFrontmostBundleIdentifier() -> String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

import SwiftUI
import AppKit

/// Represents a single logged action in the agent overlay action log.
struct AgentAction: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let timestamp: Date
}

/// Manages the floating overlay window that displays the AI agent's thoughts, current task,
/// step progress, active tool, and a scrolling log of recent actions.
final class AgentOverlayManager: NSObject, ObservableObject {
    static let shared = AgentOverlayManager()
    
    @Published var isVisible: Bool = false {
        didSet {
            let visible = isVisible
            Task { @MainActor in
                if visible {
                    self.showPanel()
                } else {
                    self.hidePanel()
                }
            }
        }
    }
    
    @Published var currentThought: String = "Thinking..."
    @Published var currentTask: String = "Initializing agent loop"
    
    // Step tracking
    @Published var currentStep: Int = 0
    @Published var maxSteps: Int = 100
    
    // Action log (last 5 tool actions)
    @Published var recentActions: [AgentAction] = []
    
    // Currently executing tool
    @Published var activeToolName: String? = nil
    
    private var panel: NSPanel?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Updates the state of the agent overlay (called by update_agent_status tool).
    @MainActor
    func updateState(thought: String, task: String) {
        self.currentThought = thought
        self.currentTask = task
        
        // Ensure panel is visible if state is being updated
        if !isVisible {
            isVisible = true
        }
    }
    
    /// Called before a tool starts executing. Shows the overlay and sets the active tool.
    @MainActor
    func startTool(name: String, step: Int, maxSteps: Int) {
        self.activeToolName = name
        self.currentStep = step
        self.maxSteps = maxSteps
        
        // Auto-derive a human-readable thought from the tool name
        self.currentThought = thoughtForTool(name)
        
        if !isVisible {
            isVisible = true
        }
    }
    
    /// Called after a tool finishes executing. Logs the action and clears active tool.
    @MainActor
    func endTool(icon: String, label: String) {
        self.activeToolName = nil
        logAction(icon: icon, label: label)
    }
    
    /// Appends an action to the recent actions log (keeps last 5).
    @MainActor
    func logAction(icon: String, label: String) {
        let action = AgentAction(icon: icon, label: label, timestamp: Date())
        recentActions.append(action)
        if recentActions.count > 5 {
            recentActions.removeFirst(recentActions.count - 5)
        }
    }
    
    /// Resets the overlay state for a new generation cycle.
    @MainActor
    func resetForNewGeneration() {
        currentStep = 0
        recentActions.removeAll()
        activeToolName = nil
        currentThought = "Thinking..."
        currentTask = "Processing request"
    }
    
    // MARK: - Private
    
    private func thoughtForTool(_ name: String) -> String {
        switch name {
        case "open_application": return "Opening an application..."
        case "take_screenshot": return "Capturing the screen to see what's happening..."
        case "press_keys": return "Pressing keyboard shortcut..."
        case "wait": return "Waiting for the UI to update..."
        case "get_frontmost_app_info": return "Checking which app is active..."
        case "move_mouse": return "Moving the cursor..."
        case "click_mouse": return "Clicking..."
        case "type_text": return "Typing text..."
        case "execute_shell_command": return "Running a shell command..."
        case "search_files": return "Searching for files..."
        case "read_file": return "Reading file contents..."
        case "list_directory": return "Browsing directory..."
        case "get_calendar_events": return "Checking calendar..."
        case "request_screenshot": return "Loading screenshot..."
        case "update_agent_status": return "Updating status..."
        default: return "Working..."
        }
    }
    
    @MainActor
    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFront(nil)
    }
    
    @MainActor
    private func hidePanel() {
        panel?.orderOut(nil)
    }
    
    @MainActor
    private func createPanel() {
        let view = AgentOverlayView(manager: self)
        let hostingView = NSHostingView(rootView: view)
        
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        newPanel.ignoresMouseEvents = true // Let clicks pass through to the OS beneath
        newPanel.contentView = hostingView
        
        // Position it in the bottom-right corner of the main screen
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.maxX - 340 // 320 width + 20 margin
            let y = visibleFrame.minY + 20  // 20 margin from bottom
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.panel = newPanel
    }
}

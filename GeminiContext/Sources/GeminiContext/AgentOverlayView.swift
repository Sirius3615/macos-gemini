import SwiftUI

struct AgentOverlayView: View {
    @ObservedObject var manager: AgentOverlayManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with step counter
            HStack {
                Image(systemName: "circle.hexagonpath.fill")
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Agent Active")
                    .font(.system(size: 11, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.cyan)
                Spacer()
                Text("Step \(manager.currentStep)/\(manager.maxSteps)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan.opacity(0.7))
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * progressFraction), height: 3)
                        .animation(.easeInOut(duration: 0.3), value: manager.currentStep)
                }
            }
            .frame(height: 3)
            
            // Active tool indicator
            if let toolName = manager.activeToolName {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text(humanReadableToolName(toolName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.cyan.opacity(0.15))
                )
            }
            
            // Thought
            VStack(alignment: .leading, spacing: 2) {
                Text("THINKING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(manager.currentThought)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .animation(.easeInOut(duration: 0.2), value: manager.currentThought)
            }
            
            // Recent actions log
            if !manager.recentActions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIONS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(manager.recentActions.suffix(3)) { action in
                        HStack(spacing: 5) {
                            Text(action.icon)
                                .font(.system(size: 10))
                            Text(action.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }
                .transition(.opacity)
            }
            
            // ESC hint
            HStack {
                Spacer()
                Text("Press ESC to stop")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.4), Color.blue.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.cyan.opacity(0.15), radius: 12, x: 0, y: 0)
    }
    
    private var progressFraction: CGFloat {
        guard manager.maxSteps > 0 else { return 0 }
        return CGFloat(manager.currentStep) / CGFloat(manager.maxSteps)
    }
    
    private func humanReadableToolName(_ name: String) -> String {
        switch name {
        case "open_application": return "Opening application…"
        case "take_screenshot": return "Capturing screen…"
        case "press_keys": return "Pressing keys…"
        case "wait": return "Waiting…"
        case "get_frontmost_app_info": return "Checking active app…"
        case "move_mouse": return "Moving cursor…"
        case "click_mouse": return "Clicking…"
        case "type_text": return "Typing…"
        case "execute_shell_command": return "Running command…"
        case "search_files": return "Searching files…"
        case "read_file": return "Reading file…"
        case "list_directory": return "Listing directory…"
        case "get_calendar_events": return "Checking calendar…"
        case "request_screenshot": return "Loading screenshot…"
        case "update_agent_status": return "Updating status…"
        default: return "Working…"
        }
    }
}

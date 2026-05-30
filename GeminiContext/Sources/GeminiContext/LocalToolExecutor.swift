import Foundation
import AppKit

/// Shared local tool execution logic used by all AI service providers.
/// Handles file system tools, calendar access, screenshot gating, computer control,
/// and application interaction tools.
final class LocalToolExecutor {

    static let shared = LocalToolExecutor()

    /// The workspace path to scope file operations to.
    let workspacePath = "/Users/ivanbegonja/Documents/macos gemini"

    /// Deferred screenshot data — held back until the AI requests it.
    var deferredScreenshotData: Data?
    
    /// Screen capture manager for mid-loop screenshots.
    private let screenCaptureManager = ScreenCaptureManager()

    private init() {}

    // MARK: - Tool Dispatch

    /// Executes a tool by name with the given arguments.
    /// Returns the result string, and optionally the screenshot data if `request_screenshot` or `take_screenshot` was called.
    func execute(toolName: String, args: [String: String]?) -> (result: String, screenshotData: Data?) {
        switch toolName {
        case "list_directory":
            let path = args?["path"] ?? workspacePath
            return (listDirectory(path: path), nil)

        case "search_files":
            let query = args?["query"] ?? ""
            let matches = searchFiles(query: query)
            if matches.isEmpty {
                return ("No matching files found for query '\(query)'. Try a more specific filename or use list_directory to browse the project structure.", nil)
            }
            return (matches.joined(separator: "\n"), nil)

        case "read_file":
            let path = args?["path"] ?? ""
            return (readFile(path: path), nil)

        case "get_calendar_events":
            let startDate = args?["start_date"] ?? ""
            let endDate = args?["end_date"] ?? ""
            return (getCalendarEvents(startDateStr: startDate, endDateStr: endDate), nil)

        case "request_screenshot":
            if let data = deferredScreenshotData {
                deferredScreenshotData = nil // Clear after use
                return ("Screenshot provided. Analyze the image that has been attached to answer the user's question.", data)
            } else {
                return ("No screenshot is available for this session.", nil)
            }

        case "move_mouse":
            let xStr = args?["x"] ?? "0"
            let yStr = args?["y"] ?? "0"
            if let x = Double(xStr), let y = Double(yStr) {
                return (moveMouse(x: CGFloat(x), y: CGFloat(y)), nil)
            }
            return ("Error: Invalid coordinates", nil)
            
        case "click_mouse":
            return (clickMouse(), nil)
            
        case "type_text":
            let text = args?["text"] ?? ""
            return (typeText(text: text), nil)
            
        case "execute_shell_command":
            let command = args?["command"] ?? ""
            return (executeShellCommand(command: command), nil)
            
        case "update_agent_status":
            let thought = args?["thought"] ?? ""
            let task = args?["task"] ?? ""
            return (updateAgentStatus(thought: thought, task: task), nil)
            
        case "read_memory":
            return (MemoryManager.shared.readMemory(), nil)
            
        case "update_memory":
            let content = args?["content"] ?? ""
            return (MemoryManager.shared.updateMemory(content: content), nil)
            
        // MARK: New App Interaction Tools
            
        case "open_application":
            let appName = args?["app_name"] ?? ""
            let filePath = args?["file_path"]
            return (openApplication(appName: appName, filePath: filePath), nil)
            
        case "take_screenshot":
            return takeScreenshotSync()
            
        case "press_keys":
            let keys = args?["keys"] ?? ""
            return (pressKeys(keys: keys), nil)
            
        case "wait":
            let msStr = args?["milliseconds"] ?? "1000"
            let ms = Int(msStr) ?? 1000
            return (waitMilliseconds(ms: ms), nil)
            
        case "get_frontmost_app_info":
            return (getFrontmostAppInfo(), nil)

        default:
            return ("Error: Unknown function '\(toolName)' or missing arguments. Available tools: search_files, read_file, list_directory, get_calendar_events, request_screenshot, move_mouse, click_mouse, type_text, execute_shell_command, update_agent_status, open_application, take_screenshot, press_keys, wait, get_frontmost_app_info, read_memory, update_memory.", nil)
        }
    }

    // MARK: - Computer Control Tools
    
    func moveMouse(x: CGFloat, y: CGFloat) -> String {
        let point = CGPoint(x: x, y: y)
        guard let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return "Failed to create mouse event"
        }
        moveEvent.post(tap: .cghidEventTap)
        return "Mouse moved to \(x), \(y)"
    }
    
    func clickMouse() -> String {
        guard let loc = CGEvent(source: nil)?.location else { return "Could not get cursor location" }
        
        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: loc, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: loc, mouseButton: .left) else {
            return "Failed to create click event"
        }
        
        mouseDown.post(tap: .cghidEventTap)
        usleep(50000) // 50ms
        mouseUp.post(tap: .cghidEventTap)
        return "Clicked at \(loc.x), \(loc.y)"
    }
    
    func typeText(text: String) -> String {
        // AppleScript is robust for typing arbitrary strings with correct keyboard layouts
        // Escape quotes and backslashes
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            keystroke "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                return "Failed to type text: \(error)"
            }
            return "Typed successfully."
        }
        return "Failed to initialize AppleScript"
    }
    
    func executeShellCommand(command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = errorPipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: data, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            var result = ""
            if !output.isEmpty { result += output }
            if !errorOutput.isEmpty { result += "\nError: \(errorOutput)" }
            if result.isEmpty { result = "Command executed successfully with no output." }
            
            return String(result.prefix(10000)) // Limit output length
        } catch {
            return "Failed to execute command: \(error.localizedDescription)"
        }
    }
    
    func updateAgentStatus(thought: String, task: String) -> String {
        Task { @MainActor in
            AgentOverlayManager.shared.updateState(thought: thought, task: task)
        }
        return "Status updated"
    }
    
    // MARK: - App Interaction Tools
    
    /// Opens an application by name or bundle ID, optionally opening a specific file with it.
    func openApplication(appName: String, filePath: String?) -> String {
        guard !appName.isEmpty else {
            return "Error: app_name is required."
        }
        
        let workspace = NSWorkspace.shared
        
        // If a file path is provided, open the file with the specified app
        if let filePath = filePath, !filePath.isEmpty {
            let fileURL = URL(fileURLWithPath: filePath)
            guard FileManager.default.fileExists(atPath: filePath) else {
                return "Error: File does not exist at path: \(filePath)"
            }
            
            // Try to find the app URL
            if let appURL = findAppURL(name: appName) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                
                // Use semaphore to make this synchronous
                let semaphore = DispatchSemaphore(value: 0)
                var resultMsg = ""
                
                workspace.open([fileURL], withApplicationAt: appURL, configuration: config) { app, error in
                    if let error = error {
                        resultMsg = "Error opening file with \(appName): \(error.localizedDescription)"
                    } else {
                        resultMsg = "Opened '\(filePath)' with \(appName). The app should now be active. Use wait (1000-2000ms) then take_screenshot to see the result."
                    }
                    semaphore.signal()
                }
                semaphore.wait()
                return resultMsg
            } else {
                return "Error: Could not find application '\(appName)'. Try using the exact app name (e.g., 'Pages', 'Preview', 'TextEdit') or its bundle ID."
            }
        }
        
        // Just open the app (no file)
        if let appURL = findAppURL(name: appName) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            
            let semaphore = DispatchSemaphore(value: 0)
            var resultMsg = ""
            
            workspace.openApplication(at: appURL, configuration: config) { app, error in
                if let error = error {
                    resultMsg = "Error opening \(appName): \(error.localizedDescription)"
                } else {
                    resultMsg = "Opened \(appName). The app should now be active. Use wait (1000-2000ms) then take_screenshot to see what's on screen."
                }
                semaphore.signal()
            }
            semaphore.wait()
            return resultMsg
        }
        
        // Fallback: try shell open command
        let shellResult = executeShellCommand(command: "open -a \"\(appName)\"")
        if shellResult.contains("Error") || shellResult.contains("Unable") {
            return "Error: Could not find or open application '\(appName)'. Try the exact app name (e.g., 'Pages', 'Preview', 'TextEdit')."
        }
        return "Opened \(appName) via shell. Use wait (1000-2000ms) then take_screenshot to see the result."
    }
    
    /// Finds the URL for an application by name or bundle ID.
    private func findAppURL(name: String) -> URL? {
        let workspace = NSWorkspace.shared
        
        // Try as bundle ID first
        if let url = workspace.urlForApplication(withBundleIdentifier: name) {
            return url
        }
        
        // Try as app name in /Applications
        let appPaths = [
            "/Applications/\(name).app",
            "/Applications/\(name)",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app"
        ]
        
        for path in appPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        // Try mdfind for non-standard locations
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.arguments = ["-c", "mdfind 'kMDItemKind == \"Application\"' | grep -i '\(name)' | head -1"]
        task.launchPath = "/bin/zsh"
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        } catch {}
        
        return nil
    }
    
    /// Captures a fresh screenshot mid-loop. This runs synchronously using a semaphore.
    func takeScreenshotSync() -> (result: String, screenshotData: Data?) {
        let semaphore = DispatchSemaphore(value: 0)
        var capturedData: Data? = nil
        var errorMsg: String? = nil
        
        Task {
            do {
                let data = try await screenCaptureManager.captureCurrentDisplayAsData()
                capturedData = data
            } catch {
                errorMsg = "Failed to capture screenshot: \(error.localizedDescription)"
            }
            semaphore.signal()
        }
        
        // Wait up to 10 seconds for capture
        let result = semaphore.wait(timeout: .now() + 10)
        
        if result == .timedOut {
            return ("Error: Screenshot capture timed out.", nil)
        }
        
        if let error = errorMsg {
            return (error, nil)
        }
        
        if let data = capturedData {
            return ("Screenshot captured successfully. Analyze the attached image to see the current state of the screen.", data)
        }
        
        return ("Error: Screenshot capture returned no data.", nil)
    }
    
    /// Presses keyboard shortcuts using AppleScript System Events.
    /// Format: "command+shift+s", "command+o", "return", "escape", "tab", "down", "up"
    func pressKeys(keys: String) -> String {
        guard !keys.isEmpty else {
            return "Error: keys parameter is required."
        }
        
        let parts = keys.lowercased().components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var modifiers: [String] = []
        var keyToPress: String? = nil
        
        for part in parts {
            switch part {
            case "command", "cmd": modifiers.append("command down")
            case "shift": modifiers.append("shift down")
            case "option", "alt": modifiers.append("option down")
            case "control", "ctrl": modifiers.append("control down")
            default: keyToPress = part
            }
        }
        
        guard let key = keyToPress else {
            return "Error: No key specified. Format: 'command+s', 'return', 'escape', etc."
        }
        
        // Map special key names to AppleScript key codes
        let specialKeys: [String: (code: Int, isKeyCode: Bool)] = [
            "return": (36, true), "enter": (36, true),
            "escape": (53, true), "esc": (53, true),
            "tab": (48, true),
            "delete": (51, true), "backspace": (51, true),
            "space": (49, true),
            "up": (126, true), "down": (125, true),
            "left": (123, true), "right": (124, true),
            "f1": (122, true), "f2": (120, true), "f3": (99, true),
            "f4": (118, true), "f5": (96, true), "f6": (97, true),
            "f7": (98, true), "f8": (100, true), "f9": (101, true),
            "f10": (109, true), "f11": (103, true), "f12": (111, true),
        ]
        
        let script: String
        let modifierClause = modifiers.isEmpty ? "" : " using {\(modifiers.joined(separator: ", "))}"
        
        if let special = specialKeys[key] {
            script = """
            tell application "System Events"
                key code \(special.code)\(modifierClause)
            end tell
            """
        } else if key.count == 1 {
            let escaped = key.replacingOccurrences(of: "\"", with: "\\\"")
            script = """
            tell application "System Events"
                keystroke "\(escaped)"\(modifierClause)
            end tell
            """
        } else {
            return "Error: Unrecognized key '\(key)'. Use single characters (a-z, 0-9) or special keys (return, escape, tab, up, down, left, right, space, delete, f1-f12)."
        }
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                return "Failed to press keys: \(error)"
            }
            return "Pressed \(keys) successfully. Use wait then take_screenshot to see the result."
        }
        return "Failed to initialize AppleScript for key press."
    }
    
    /// Waits for a specified number of milliseconds (capped at 5000ms).
    func waitMilliseconds(ms: Int) -> String {
        let capped = min(max(ms, 50), 5000)
        usleep(UInt32(capped) * 1000)
        return "Waited \(capped)ms. You can now take_screenshot to see the current state."
    }
    
    /// Returns information about the currently frontmost application.
    func getFrontmostAppInfo() -> String {
        let workspace = NSWorkspace.shared
        guard let app = workspace.frontmostApplication else {
            return "Error: Could not determine the frontmost application."
        }
        
        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? "Unknown"
        
        // Try to get the window title via Accessibility
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        
        var windowTitle = "Unknown"
        var focusedWindow: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
            var titleValue: AnyObject?
            if AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String {
                windowTitle = title
            }
        }
        
        return """
        Frontmost Application:
          Name: \(appName)
          Bundle ID: \(bundleID)
          Window Title: \(windowTitle)
        """
    }

    // MARK: - File System Tools

    /// List contents of a directory (non-recursive, one level deep)
    func listDirectory(path: String) -> String {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return "Error: '\(path)' is not a valid directory."
        }

        do {
            let items = try fileManager.contentsOfDirectory(atPath: path)
                .filter { !$0.hasPrefix(".") } // Skip hidden files
                .sorted()

            if items.isEmpty {
                return "Directory is empty: \(path)"
            }

            var lines: [String] = ["Contents of \(path):"]
            for item in items.prefix(50) {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var itemIsDir: ObjCBool = false
                fileManager.fileExists(atPath: fullPath, isDirectory: &itemIsDir)
                if itemIsDir.boolValue {
                    lines.append("  📁 \(item)/")
                } else {
                    // Show file size
                    let attrs = try? fileManager.attributesOfItem(atPath: fullPath)
                    let size = (attrs?[.size] as? Int) ?? 0
                    let sizeStr = size > 1024 ? "\(size / 1024)KB" : "\(size)B"
                    lines.append("  📄 \(item) (\(sizeStr))")
                }
            }
            if items.count > 50 {
                lines.append("  ... and \(items.count - 50) more items")
            }
            return lines.joined(separator: "\n")
        } catch {
            return "Error listing directory: \(error.localizedDescription)"
        }
    }

    /// Search for files by name, strongly prioritizing the workspace directory
    func searchFiles(query: String) -> [String] {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let workspaceURL = URL(fileURLWithPath: workspacePath)

        // Search workspace first with a generous limit
        let workspaceMatches = searchDirectory(url: workspaceURL, query: query, maxResults: 15, fileManager: fileManager)

        // Only search broader directories if workspace yielded few results
        var otherMatches: [String] = []
        if workspaceMatches.count < 3 {
            let otherDirs = [
                homeDir.appendingPathComponent("Documents"),
                homeDir.appendingPathComponent("Downloads"),
                homeDir.appendingPathComponent("Desktop")
            ]
            for dir in otherDirs {
                // Skip if this is the workspace parent (avoid duplicates)
                if dir.path == workspaceURL.deletingLastPathComponent().path { continue }
                guard fileManager.fileExists(atPath: dir.path) else { continue }
                let found = searchDirectory(url: dir, query: query, maxResults: 5, fileManager: fileManager)
                otherMatches.append(contentsOf: found)
                if otherMatches.count >= 5 { break }
            }
            // Deduplicate any paths already found in workspace
            let workspaceSet = Set(workspaceMatches)
            otherMatches = otherMatches.filter { !workspaceSet.contains($0) }
        }

        // Format results with clear grouping
        var result: [String] = []
        if !workspaceMatches.isEmpty {
            result.append("── Workspace (\(workspaceMatches.count) match\(workspaceMatches.count == 1 ? "" : "es")) ──")
            result.append(contentsOf: workspaceMatches)
        }
        if !otherMatches.isEmpty {
            result.append("── Other locations (\(otherMatches.count) match\(otherMatches.count == 1 ? "" : "es")) ──")
            result.append(contentsOf: otherMatches.prefix(5))
        }
        return result
    }

    /// Helper: search a single directory for files matching a query
    private func searchDirectory(url: URL, query: String, maxResults: Int, fileManager: FileManager) -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else { return [] }

        var matches: [String] = []

        for case let fileURL as URL in enumerator {
            let path = fileURL.path

            // Skip build artifacts, dependencies, and VCS directories
            if path.contains("/.build/") || path.contains("/.git/") || path.contains("/.swiftpm/") || path.contains("/DerivedData/") || path.contains("/node_modules/") {
                enumerator.skipDescendants()
                continue
            }

            let name = fileURL.lastPathComponent
            if name.localizedCaseInsensitiveContains(query) {
                matches.append(path)
                if matches.count >= maxResults {
                    return matches
                }
            }
        }
        return matches
    }

    /// Read file content as text, limits to 25k chars.
    func readFile(path: String) -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return "Error: File does not exist at path: \(path)"
        }

        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return "Error: Path \(path) is a directory, not a file."
        }

        guard fileManager.isReadableFile(atPath: path) else {
            return "Error: File is not readable at path: \(path)"
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let content = String(data: data, encoding: .utf8) {
                if content.count > 25000 {
                    return String(content.prefix(25000)) + "\n\n[TRUNCATED due to length...]"
                }
                return content
            } else {
                return "Error: File content is not valid UTF-8 text (might be a binary file)."
            }
        } catch {
            return "Error reading file: \(error.localizedDescription)"
        }
    }

    // MARK: - Calendar Tool

    /// Fetches calendar events for the given date range and returns a formatted string.
    func getCalendarEvents(startDateStr: String, endDateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        guard let startDate = formatter.date(from: startDateStr) else {
            return "Error: Invalid start_date format '\(startDateStr)'. Use YYYY-MM-DD format."
        }
        // Default end date to end of start date if not provided
        let endDate: Date
        if endDateStr.isEmpty {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        } else {
            guard let parsed = formatter.date(from: endDateStr) else {
                return "Error: Invalid end_date format '\(endDateStr)'. Use YYYY-MM-DD format."
            }
            // Set to end of the end date
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: parsed) ?? parsed
        }

        return CalendarService.shared.fetchEventsFormatted(from: startDate, to: endDate)
    }

    // MARK: - Tool Declarations

    /// Returns the full set of tool/function declarations for use in API requests.
    func toolDeclarations() -> [[String: Any]] {
        return [
            [
                "name": "read_memory",
                "description": "Read the AI memory markdown file. Use this to see what you have remembered about the user.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "update_memory",
                "description": "Update the AI memory markdown file. Overwrites the existing memory. You should first read_memory, modify the text, and then write it back to remember user preferences, useful links, etc.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "content": [
                            "type": "STRING",
                            "description": "The full new markdown content to save."
                        ]
                    ],
                    "required": ["content"]
                ]
            ],
            [
                "name": "list_directory",
                "description": "List the files and subdirectories in a directory. START HERE to explore the project structure before searching. The current workspace is at \(workspacePath). Use this first to understand the project layout, then read specific files.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "path": [
                            "type": "STRING",
                            "description": "Absolute path of the directory to list. Start with '\(workspacePath)' and drill down into subdirectories."
                        ]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "search_files",
                "description": "Search for files by name within the workspace (\(workspacePath)). Only use this when you know part of the filename. Results are grouped by location with workspace files listed first. For browsing project structure, use list_directory instead.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "query": [
                            "type": "STRING",
                            "description": "A specific filename or partial filename to search for (e.g. 'SettingsManager.swift' or 'ChatView'). Be as specific as possible."
                        ]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "read_file",
                "description": "Read the text contents of a local file at the specified absolute path. Use after finding the file via list_directory or search_files.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "path": [
                            "type": "STRING",
                            "description": "The absolute path of the file to read."
                        ]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "get_calendar_events",
                "description": "Retrieve the user's macOS calendar events for a specific date range. Returns event titles, times, locations, and calendar names. Use when the user asks about their schedule, meetings, appointments, or what's on their calendar.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "start_date": [
                            "type": "STRING",
                            "description": "Start date in YYYY-MM-DD format (e.g. '2025-05-25')"
                        ],
                        "end_date": [
                            "type": "STRING",
                            "description": "End date in YYYY-MM-DD format (e.g. '2025-05-26'). Defaults to end of start_date if omitted."
                        ]
                    ],
                    "required": ["start_date"]
                ]
            ],
            [
                "name": "request_screenshot",
                "description": "Request the user's current screen screenshot. ONLY call this if the user's question requires visual context — for example: 'what's on my screen', 'read this error', 'what app is open', UI analysis, or analyzing something visible. Do NOT call for general knowledge questions, coding help without screen context, math, or text-based queries.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "move_mouse",
                "description": "Move the mouse cursor to a specific absolute coordinate on the screen. Use request_screenshot or take_screenshot first to figure out where to click.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "x": ["type": "STRING", "description": "The X coordinate."],
                        "y": ["type": "STRING", "description": "The Y coordinate."]
                    ],
                    "required": ["x", "y"]
                ]
            ],
            [
                "name": "click_mouse",
                "description": "Perform a left-click at the current mouse cursor location. Usually call move_mouse first, then click_mouse.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "type_text",
                "description": "Type text on the keyboard as if the user were typing it. Useful for filling forms, search bars, or terminal inputs after clicking on them.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "text": ["type": "STRING", "description": "The exact text to type."]
                    ],
                    "required": ["text"]
                ]
            ],
            [
                "name": "execute_shell_command",
                "description": "Execute a shell command (zsh) autonomously on the user's system and return its output. Can be used for powerful OS actions, file modifications, or reading state.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "command": ["type": "STRING", "description": "The shell command to execute."]
                    ],
                    "required": ["command"]
                ]
            ],
            [
                "name": "update_agent_status",
                "description": "Update your current thought and task status on the screen overlay. ALWAYS call this when moving between major steps of a complex task so the user knows what you are doing.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "thought": ["type": "STRING", "description": "A short sentence describing your current internal thought process or what you are trying to figure out."],
                        "task": ["type": "STRING", "description": "A short phrase describing your active task (e.g., 'Searching for settings file')."]
                    ],
                    "required": ["thought", "task"]
                ]
            ],
            // MARK: New App Interaction Tools
            [
                "name": "open_application",
                "description": "Open a macOS application by name. Can also open a specific file with a specific app. Use this to launch apps like Pages, Finder, Preview, TextEdit, Safari, Numbers, Keynote, etc. After opening, use wait(1000-2000ms) then take_screenshot to see the result.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "app_name": [
                            "type": "STRING",
                            "description": "The name of the application to open (e.g., 'Pages', 'Preview', 'TextEdit', 'Finder', 'Safari'). Can also be a bundle ID."
                        ],
                        "file_path": [
                            "type": "STRING",
                            "description": "Optional absolute path to a file to open with the application (e.g., '/Users/user/Documents/report.docx')."
                        ]
                    ],
                    "required": ["app_name"]
                ]
            ],
            [
                "name": "take_screenshot",
                "description": "Capture a fresh screenshot of the current screen RIGHT NOW. Use this to see what is currently displayed after opening an app, clicking, typing, or pressing keys. This is essential for multi-step tasks — always screenshot after actions to verify the result. The screenshot image will be attached for you to analyze.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ],
            [
                "name": "press_keys",
                "description": "Press a keyboard shortcut or key combination. Format: modifier keys joined with '+' followed by the key. Examples: 'command+o' (open file), 'command+s' (save), 'command+shift+s' (save as), 'command+n' (new), 'command+c' (copy), 'command+v' (paste), 'return' (enter/confirm), 'escape' (cancel), 'tab', 'up', 'down', 'left', 'right'. After pressing, use wait then take_screenshot to see the result.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "keys": [
                            "type": "STRING",
                            "description": "The key combination to press. Examples: 'command+o', 'command+shift+s', 'return', 'escape', 'tab', 'command+a'."
                        ]
                    ],
                    "required": ["keys"]
                ]
            ],
            [
                "name": "wait",
                "description": "Wait for a specified number of milliseconds before continuing. Use after open_application, press_keys, or click_mouse to give the UI time to update before taking a screenshot. Typical values: 500ms for simple clicks, 1000-2000ms for opening apps or dialogs.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [
                        "milliseconds": [
                            "type": "STRING",
                            "description": "Number of milliseconds to wait (50-5000). Recommend 1000-2000 for app launches, 500 for UI transitions."
                        ]
                    ],
                    "required": ["milliseconds"]
                ]
            ],
            [
                "name": "get_frontmost_app_info",
                "description": "Get information about the currently active (frontmost) application, including its name, bundle ID, and window title. Use to confirm which app is active before interacting with it.",
                "parameters": [
                    "type": "OBJECT",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ]
            ]
        ]
    }

    /// Returns OpenAI-compatible tool declarations for Ollama.
    func openAIToolDeclarations() -> [[String: Any]] {
        return toolDeclarations().map { decl in
            [
                "type": "function",
                "function": decl
            ]
        }
    }
}

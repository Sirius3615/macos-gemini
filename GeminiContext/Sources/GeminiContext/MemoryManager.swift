import Foundation

/// Manages the AI's persistent memory markdown file.
final class MemoryManager {
    static let shared = MemoryManager()
    
    let memoryFileURL: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        memoryFileURL = documentsPath.appendingPathComponent("AI_Memory.md")
        
        // Create if doesn't exist
        if !FileManager.default.fileExists(atPath: memoryFileURL.path) {
            let initialContent = """
            # AI Memory
            This file is used by the AI to remember things about the user. The AI can read and update this file automatically to remember user preferences, useful links, and context.
            """
            try? initialContent.write(to: memoryFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    func readMemory() -> String {
        guard let content = try? String(contentsOf: memoryFileURL, encoding: .utf8) else {
            return ""
        }
        return content
    }
    
    func updateMemory(content: String) -> String {
        do {
            try content.write(to: memoryFileURL, atomically: true, encoding: .utf8)
            return "Memory updated successfully."
        } catch {
            return "Error updating memory: \\(error.localizedDescription)"
        }
    }
}

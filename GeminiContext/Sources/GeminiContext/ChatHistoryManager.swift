import Foundation

struct ChatSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage]
    var timestamp: Date
    var screenshotData: Data?
}

/// Manages saving and loading chat sessions to disk (Application Support).
final class ChatHistoryManager: ObservableObject {
    static let shared = ChatHistoryManager()

    @Published var sessions: [ChatSession] = []

    private let fileManager = FileManager.default
    private let sessionsDirectory: URL

    private init() {
        // Setup Application Support directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.geminicontext.app"
        sessionsDirectory = appSupport.appendingPathComponent(appBundleID).appendingPathComponent("Sessions")

        if !fileManager.fileExists(atPath: sessionsDirectory.path) {
            try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        }

        loadSessions()
    }

    /// Loads all sessions from disk, sorted by newest first.
    func loadSessions() {
        do {
            let files = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)
            var loadedSessions: [ChatSession] = []
            
            for file in files where file.pathExtension == "json" {
                let data = try Data(contentsOf: file)
                let session = try JSONDecoder().decode(ChatSession.self, from: data)
                loadedSessions.append(session)
            }
            
            self.sessions = loadedSessions.sorted(by: { $0.timestamp > $1.timestamp })
        } catch {
            print("[ChatHistoryManager] Error loading sessions: \(error)")
        }
    }

    /// Saves a session to disk.
    func saveSession(_ session: ChatSession) {
        // Update memory
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
            sessions.sort(by: { $0.timestamp > $1.timestamp })
        }

        // Write to disk
        do {
            let data = try JSONEncoder().encode(session)
            let fileURL = sessionsDirectory.appendingPathComponent("\(session.id.uuidString).json")
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ChatHistoryManager] Error saving session: \(error)")
        }
    }

    /// Deletes a specific session.
    func deleteSession(_ session: ChatSession) {
        sessions.removeAll(where: { $0.id == session.id })
        let fileURL = sessionsDirectory.appendingPathComponent("\(session.id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
    }

    /// Clears all history.
    func clearAllHistory() {
        sessions.removeAll()
        do {
            let files = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
        } catch {
            print("[ChatHistoryManager] Error clearing history: \(error)")
        }
    }
}

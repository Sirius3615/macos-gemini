import Foundation
import AppKit
import Security
import Combine
import ServiceManagement
import Carbon.HIToolbox

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "Gemini"
    case openai = "OpenAI"
    case claude = "Claude"
    case deepseek = "DeepSeek"
    case ollama = "Ollama"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .openai: return "o.circle"
        case .claude: return "c.circle"
        case .deepseek: return "d.circle"
        case .ollama: return "desktopcomputer"
        }
    }
}

/// Represents a keyboard shortcut (modifier flags + virtual key code).
struct KeyboardShortcutConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt  // NSEvent.ModifierFlags.rawValue
    
    /// Default pill shortcut: Cmd+Shift+Space
    static let defaultPill = KeyboardShortcutConfig(keyCode: UInt16(kVK_Space), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    /// Default full chat shortcut: Cmd+Shift+G
    static let defaultFullChat = KeyboardShortcutConfig(keyCode: UInt16(kVK_ANSI_G), modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }
    
    /// Human-readable display string for the shortcut.
    var displayString: String {
        var parts: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
    
    private func keyCodeToString(_ code: UInt16) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return "Key\(code)"
        }
    }
}

/// A persona configuration that wraps a name, icon, and system prompt.
struct PersonaConfig: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String
    var systemPrompt: String
    
    static let defaultPersonas: [PersonaConfig] = [
        PersonaConfig(
            name: "General Assistant",
            icon: "sparkles",
            systemPrompt: """
            You are a helpful AI assistant integrated into a macOS utility called AI Context. \
            The user can shake their mouse to capture their screen and ask you questions about it. \
            When shown a screenshot, analyze it carefully and provide helpful, contextual responses. \
            Use Markdown formatting in your responses including headers, lists, code blocks, and bold/italic text. \
            When mathematical expressions are relevant, use LaTeX notation wrapped in $ for inline and $$ for display math.

            ## Autonomous Computer Use
            You have full control of the user's Mac. For tasks that require interacting with applications:

            1. **Open apps** with `open_application` (e.g., Pages, Finder, Preview, TextEdit, Safari, Numbers).
            2. **Wait** 1000-2000ms with `wait` for the app/UI to load.
            3. **Screenshot** with `take_screenshot` to see what's on screen now.
            4. **Analyze** the screenshot to understand the current UI state.
            5. **Act** using `click_mouse`, `type_text`, `press_keys`, or `move_mouse`.
            6. **Repeat** steps 2-5 until the task is complete.

            Always follow this pattern: **act → wait → screenshot → analyze → act again**. \
            Never assume the UI has changed — always take a screenshot to verify after every action.

            Use `press_keys` for keyboard shortcuts: 'command+o' (open), 'command+s' (save), \
            'command+n' (new document), 'command+c' (copy), 'command+v' (paste), 'return' (confirm), 'escape' (cancel).

            Use `get_frontmost_app_info` to confirm which app is active before interacting.

            Use `update_agent_status` to communicate your thinking on multi-step tasks so the user can follow along.

            For reading documents: find the file with `search_files` or `list_directory`, then either `read_file` (for text) \
            or `open_application` + `take_screenshot` (for rich documents like .pages, .docx, .pdf).
            """
        ),
        PersonaConfig(
            name: "Code Reviewer",
            icon: "chevron.left.forwardslash.chevron.right",
            systemPrompt: """
            You are an expert code reviewer integrated into a macOS utility. \
            When shown code or screenshots of code, provide detailed, actionable code reviews. \
            Focus on: code quality, potential bugs, performance issues, security concerns, and best practices. \
            Suggest specific improvements with code examples. Use Markdown with syntax-highlighted code blocks. \
            Be constructive but thorough — point out both strengths and areas for improvement.
            """
        ),
        PersonaConfig(
            name: "Creative Writer",
            icon: "pencil.and.outline",
            systemPrompt: """
            You are a creative writing assistant. Help the user with writing tasks including \
            drafting emails, documentation, blog posts, marketing copy, and creative content. \
            Adapt your tone and style to the user's needs. Provide well-structured, engaging text. \
            When shown screenshots, help describe or write about what you see. \
            Use rich Markdown formatting to structure your responses.
            """
        )
    ]
}

/// Manages persistent app settings including API key (stored in Keychain)
/// and selected model preference (stored in UserDefaults).
final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    // Keychain constants
    private let keychainService = "com.geminicontext.app"
    private let keychainAccountBase = "api-key"

    // UserDefaults keys
    private let modelKey = "selectedModelId"
    private let providerKey = "activeAIProvider"
    private let systemPromptKey = "customSystemPrompt"
    private let shakeEnabledKey = "isShakeEnabled"
    private let chatResetMinutesKey = "chatResetMinutes"
    private let shortcutEnabledKey = "isShortcutEnabled"
    private let pillShortcutKey = "pillShortcut"
    private let fullChatShortcutKey = "fullChatShortcut"
    private let personasKey = "customPersonas"
    private let activePersonaIndexKey = "activePersonaIndex"
    private let ollamaEndpointKey = "ollamaEndpoint"
    private let ollamaModelNameKey = "ollamaModelName"
    private let smartImageGatingKey = "smartImageGating"

    @Published var activeProvider: AIProvider {
        didSet { UserDefaults.standard.set(activeProvider.rawValue, forKey: providerKey) }
    }

    @Published var geminiApiKey: String {
        didSet { saveAPIKeyToKeychain(geminiApiKey, provider: .gemini) }
    }
    @Published var openaiApiKey: String {
        didSet { saveAPIKeyToKeychain(openaiApiKey, provider: .openai) }
    }
    @Published var claudeApiKey: String {
        didSet { saveAPIKeyToKeychain(claudeApiKey, provider: .claude) }
    }
    @Published var deepseekApiKey: String {
        didSet { saveAPIKeyToKeychain(deepseekApiKey, provider: .deepseek) }
    }

    @Published var ollamaEndpoint: String {
        didSet { UserDefaults.standard.set(ollamaEndpoint, forKey: ollamaEndpointKey) }
    }
    
    @Published var ollamaModelName: String {
        didSet { UserDefaults.standard.set(ollamaModelName, forKey: ollamaModelNameKey) }
    }

    @Published var selectedModelId: String {
        didSet { UserDefaults.standard.set(selectedModelId, forKey: modelKey) }
    }

    @Published var isShakeEnabled: Bool {
        didSet { UserDefaults.standard.set(isShakeEnabled, forKey: shakeEnabledKey) }
    }
    
    @Published var chatResetMinutes: Double {
        didSet { UserDefaults.standard.set(chatResetMinutes, forKey: chatResetMinutesKey) }
    }
    
    @Published var isShortcutEnabled: Bool {
        didSet { UserDefaults.standard.set(isShortcutEnabled, forKey: shortcutEnabledKey) }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[GeminiContext] Failed to update login item: \(error)")
            }
        }
    }
    
    @Published var pillShortcut: KeyboardShortcutConfig {
        didSet { saveShortcut(pillShortcut, forKey: pillShortcutKey) }
    }
    
    @Published var smartImageGating: Bool {
        didSet { UserDefaults.standard.set(smartImageGating, forKey: smartImageGatingKey) }
    }
    
    @Published var fullChatShortcut: KeyboardShortcutConfig {
        didSet { saveShortcut(fullChatShortcut, forKey: fullChatShortcutKey) }
    }
    
    // MARK: - Personas
    
    @Published var personas: [PersonaConfig] {
        didSet { savePersonas() }
    }
    
    @Published var activePersonaIndex: Int {
        didSet {
            UserDefaults.standard.set(activePersonaIndex, forKey: activePersonaIndexKey)
        }
    }
    
    /// The system prompt from the active persona.
    var systemPrompt: String {
        get {
            var prompt = ""
            if activePersonaIndex >= 0 && activePersonaIndex < personas.count {
                prompt = personas[activePersonaIndex].systemPrompt
            } else {
                prompt = PersonaConfig.defaultPersonas[0].systemPrompt
            }
            
            let memoryContent = MemoryManager.shared.readMemory()
            if !memoryContent.isEmpty {
                prompt += "\n\n## User Memory\nHere is information you have remembered about the user. You can use update_memory to modify this.\n" + memoryContent
            }
            
            return prompt
        }
    }
    
    /// The active persona config.
    var activePersona: PersonaConfig {
        guard activePersonaIndex >= 0, activePersonaIndex < personas.count else {
            return PersonaConfig.defaultPersonas[0]
        }
        return personas[activePersonaIndex]
    }

    var selectedModel: GeminiModel {
        get { GeminiModel(rawValue: selectedModelId) ?? .pro31Preview }
        set { selectedModelId = newValue.rawValue }
    }

    var hasAPIKey: Bool {
        switch activeProvider {
        case .gemini: return !geminiApiKey.isEmpty
        case .openai: return !openaiApiKey.isEmpty
        case .claude: return !claudeApiKey.isEmpty
        case .deepseek: return !deepseekApiKey.isEmpty
        case .ollama: return !ollamaModelName.isEmpty
        }
    }

    var activeAPIKey: String {
        switch activeProvider {
        case .gemini: return geminiApiKey
        case .openai: return openaiApiKey
        case .claude: return claudeApiKey
        case .deepseek: return deepseekApiKey
        case .ollama: return "" // Ollama doesn't need an API key
        }
    }

    private init() {
        // Load from persistent storage
        if let providerStr = UserDefaults.standard.string(forKey: providerKey),
           let provider = AIProvider(rawValue: providerStr) {
            self.activeProvider = provider
        } else {
            self.activeProvider = .gemini
        }

        self.selectedModelId = UserDefaults.standard.string(forKey: modelKey) ?? GeminiModel.pro31Preview.rawValue
            
        self.isShakeEnabled = UserDefaults.standard.object(forKey: shakeEnabledKey) as? Bool ?? true
        self.chatResetMinutes = UserDefaults.standard.object(forKey: chatResetMinutesKey) as? Double ?? 20.0
        self.isShortcutEnabled = UserDefaults.standard.object(forKey: shortcutEnabledKey) as? Bool ?? false
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.pillShortcut = SettingsManager.loadShortcut(forKey: "pillShortcut") ?? .defaultPill
        self.fullChatShortcut = SettingsManager.loadShortcut(forKey: "fullChatShortcut") ?? .defaultFullChat
        self.smartImageGating = UserDefaults.standard.object(forKey: smartImageGatingKey) as? Bool ?? true
        self.ollamaEndpoint = UserDefaults.standard.string(forKey: ollamaEndpointKey) ?? "http://localhost:11434"
        self.ollamaModelName = UserDefaults.standard.string(forKey: ollamaModelNameKey) ?? ""
        
        // Load personas
        self.activePersonaIndex = UserDefaults.standard.object(forKey: activePersonaIndexKey) as? Int ?? 0
        if let data = UserDefaults.standard.data(forKey: personasKey),
           let loaded = try? JSONDecoder().decode([PersonaConfig].self, from: data),
           !loaded.isEmpty {
            self.personas = loaded
        } else {
            self.personas = PersonaConfig.defaultPersonas
        }
        
        self.geminiApiKey = ""
        self.openaiApiKey = ""
        self.claudeApiKey = ""
        self.deepseekApiKey = ""
        
        self.geminiApiKey = loadAPIKeyFromKeychain(provider: .gemini) ?? ""
        self.openaiApiKey = loadAPIKeyFromKeychain(provider: .openai) ?? ""
        self.claudeApiKey = loadAPIKeyFromKeychain(provider: .claude) ?? ""
        self.deepseekApiKey = loadAPIKeyFromKeychain(provider: .deepseek) ?? ""
    }

    // MARK: - Keychain Operations

    private func saveAPIKeyToKeychain(_ key: String, provider: AIProvider) {
        let account = "\(keychainAccountBase)-\(provider.rawValue)"
        
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadAPIKeyFromKeychain(provider: AIProvider) -> String? {
        let account = "\(keychainAccountBase)-\(provider.rawValue)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Shortcut Persistence
    
    private func saveShortcut(_ shortcut: KeyboardShortcutConfig, forKey key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private static func loadShortcut(forKey key: String) -> KeyboardShortcutConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyboardShortcutConfig.self, from: data)
    }
    
    // MARK: - Persona Persistence
    
    private func savePersonas() {
        if let data = try? JSONEncoder().encode(personas) {
            UserDefaults.standard.set(data, forKey: personasKey)
        }
    }
}

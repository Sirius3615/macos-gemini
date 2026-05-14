import Foundation
import Security
import Combine

enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "Gemini"
    case openai = "OpenAI"
    case claude = "Claude"
    case deepseek = "DeepSeek"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .openai: return "o.circle"
        case .claude: return "c.circle"
        case .deepseek: return "d.circle"
        }
    }
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

    @Published var selectedModelId: String {
        didSet { UserDefaults.standard.set(selectedModelId, forKey: modelKey) }
    }

    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: systemPromptKey) }
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
        }
    }

    var activeAPIKey: String {
        switch activeProvider {
        case .gemini: return geminiApiKey
        case .openai: return openaiApiKey
        case .claude: return claudeApiKey
        case .deepseek: return deepseekApiKey
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
        self.systemPrompt = UserDefaults.standard.string(forKey: systemPromptKey) ?? """
            You are a helpful AI assistant integrated into a macOS utility called AI Context. \
            The user can shake their mouse to capture their screen and ask you questions about it. \
            When shown a screenshot, analyze it carefully and provide helpful, contextual responses. \
            Use Markdown formatting in your responses including headers, lists, code blocks, and bold/italic text. \
            When mathematical expressions are relevant, use LaTeX notation wrapped in $ for inline and $$ for display math.
            """
            
        self.isShakeEnabled = UserDefaults.standard.object(forKey: shakeEnabledKey) as? Bool ?? true
        self.chatResetMinutes = UserDefaults.standard.object(forKey: chatResetMinutesKey) as? Double ?? 20.0
        self.isShortcutEnabled = UserDefaults.standard.object(forKey: shortcutEnabledKey) as? Bool ?? false
        
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
}

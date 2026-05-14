import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case providers = "Providers & Models"
    var id: String { rawValue }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Spacer().frame(height: 24)
                
                Label {
                    Text("General")
                } icon: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.gray)
                        .cornerRadius(5)
                }
                .tag(SettingsTab.general)
                
                Label {
                    Text("Providers & Models")
                } icon: {
                    Image(systemName: "cpu.fill")
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.blue)
                        .cornerRadius(5)
                }
                .tag(SettingsTab.providers)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .providers:
                    ProvidersSettingsView()
                }
            }
            .padding(.top, 24)
        }
        .frame(width: 700, height: 500)
    }
}

struct GeneralSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @EnvironmentObject private var shakeDetector: ShakeDetector
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: .constant(false))
                    .toggleStyle(.switch)
                    .disabled(true)
                
                Toggle("Enable Shake to Activate", isOn: $shakeDetector.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: shakeDetector.isEnabled) { _, newValue in
                        settings.isShakeEnabled = newValue
                    }
                
                Toggle("Enable Global Keyboard Shortcut", isOn: $settings.isShortcutEnabled)
                    .toggleStyle(.switch)
            } header: {
                Text("Activation Behaviour")
            } footer: {
                Text("When enabled, you can quickly invoke the AI by either shaking your mouse or pressing Cmd+Shift+Space.")
            }
            
            Section {
                HStack {
                    Text("Reset Chat Memory")
                    Spacer()
                    Picker("", selection: $settings.chatResetMinutes) {
                        Text("After 5 minutes").tag(5.0)
                        Text("After 10 minutes").tag(10.0)
                        Text("After 20 minutes").tag(20.0)
                        Text("After 30 minutes").tag(30.0)
                        Text("After 1 hour").tag(60.0)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            } header: {
                Text("Chat Session")
            } footer: {
                Text("If you don't interact for this duration, your next message will start a fresh chat.")
            }
        }
        .formStyle(.grouped)
    }
}

struct ProvidersSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(.purple).frame(width: 20)
                    SecureField("Gemini API Key", text: $settings.geminiApiKey)
                }
                HStack {
                    Image(systemName: "o.square").foregroundStyle(.green).frame(width: 20)
                    SecureField("OpenAI API Key", text: $settings.openaiApiKey)
                }
                HStack {
                    Image(systemName: "c.square").foregroundStyle(.orange).frame(width: 20)
                    SecureField("Claude API Key", text: $settings.claudeApiKey)
                }
                HStack {
                    Image(systemName: "d.circle").foregroundStyle(.blue).frame(width: 20)
                    SecureField("DeepSeek API Key", text: $settings.deepseekApiKey)
                }
            } header: {
                Text("API Authentication")
            } footer: {
                Text("Your keys are securely stored in the macOS Keychain.")
            }
            
            Section {
                Picker("Active Provider", selection: $settings.activeProvider) {
                    if !settings.geminiApiKey.isEmpty { Label("Google Gemini", systemImage: "sparkles").tag(AIProvider.gemini) }
                    if !settings.openaiApiKey.isEmpty { Label("OpenAI", systemImage: "o.square").tag(AIProvider.openai) }
                    if !settings.claudeApiKey.isEmpty { Label("Anthropic Claude", systemImage: "c.square").tag(AIProvider.claude) }
                    if !settings.deepseekApiKey.isEmpty { Label("DeepSeek", systemImage: "d.circle").tag(AIProvider.deepseek) }
                    
                    if settings.geminiApiKey.isEmpty && settings.openaiApiKey.isEmpty && settings.claudeApiKey.isEmpty && settings.deepseekApiKey.isEmpty {
                        Text("No API Key configured").tag(AIProvider.gemini)
                    }
                }
                
                Picker("Preferred Model", selection: $settings.selectedModelId) {
                    switch settings.activeProvider {
                    case .gemini:
                        Text("Gemini 3.1 Pro").tag("gemini-3.1-pro-preview")
                        Text("Gemini 3 Flash").tag("gemini-3-flash-preview")
                        Text("Gemini 3.1 Flash-Lite").tag("gemini-3.1-flash-lite")
                        Text("Gemini 2.5 Pro").tag("gemini-2.5-pro")
                        Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                    case .openai:
                        Text("GPT-5.5").tag("gpt-5.5")
                        Text("GPT-5.5 Pro").tag("gpt-5.5-pro")
                        Text("GPT-5.4 Mini").tag("gpt-5.4-mini")
                        Text("GPT-5.4 Nano").tag("gpt-5.4-nano")
                        Text("GPT-4.1").tag("gpt-4.1")
                        Text("GPT-4.1 Mini").tag("gpt-4.1-mini")
                        Text("GPT-4.1 Nano").tag("gpt-4.1-nano")
                    case .claude:
                        Text("Claude Opus 4.6").tag("claude-opus-4-6")
                        Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                        Text("Claude Haiku 4.5").tag("claude-haiku-4-5")
                    case .deepseek:
                        Text("DeepSeek-V4-Pro").tag("deepseek-v4-pro")
                        Text("DeepSeek-V4-Flash").tag("deepseek-v4-flash")
                    }
                }
            } header: {
                Text("Model Configuration")
            }
        }
        .formStyle(.grouped)
    }
}

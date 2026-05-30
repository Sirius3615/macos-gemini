import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case providers = "Providers & Models"
    case personas = "Personas"
    var id: String { rawValue }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
            
            ProvidersSettingsView()
                .tabItem {
                    Label("Providers & Models", systemImage: "cpu")
                }
                .tag(SettingsTab.providers)
            
            PersonasSettingsView()
                .tabItem {
                    Label("Personas", systemImage: "person.2")
                }
                .tag(SettingsTab.personas)
        }
        .frame(width: 600, height: 500)
        .padding()
        .onAppear {
            ChatWindowManager.shared.updateActivationPolicy()
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" || $0.title == "Settings" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .onDisappear {
            DispatchQueue.main.async {
                ChatWindowManager.shared.updateActivationPolicy()
            }
        }
    }
}

struct GeneralSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @EnvironmentObject private var shakeDetector: ShakeDetector
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                
                Toggle("Enable Shake to Activate", isOn: $shakeDetector.isEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: shakeDetector.isEnabled) { _, newValue in
                        settings.isShakeEnabled = newValue
                    }
            } header: {
                Text("Activation")
            }
            
            Section {
                Toggle("Enable Global Keyboard Shortcuts", isOn: $settings.isShortcutEnabled)
                    .toggleStyle(.switch)
                
                if settings.isShortcutEnabled {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quick Pill")
                                .font(.system(size: 13, weight: .medium))
                            Text("Opens the compact input bar at cursor")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        KeyboardShortcutRecorder(shortcut: $settings.pillShortcut)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full Chat")
                                .font(.system(size: 13, weight: .medium))
                            Text("Opens the expanded chat panel at cursor")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        KeyboardShortcutRecorder(shortcut: $settings.fullChatShortcut)
                    }
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Clickm a shortcut to record a new key combination. At least one modifier key (⌘, ⌃, ⌥) is required.")
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
            
            Section {
                Toggle("Smart Screenshot Mode", isOn: $settings.smartImageGating)
                    .toggleStyle(.switch)
            } header: {
                Text("Token Optimization")
            } footer: {
                Text("When enabled, screenshots are only sent when the AI determines visual context is needed. Saves tokens on text-based queries like coding help, math, or general knowledge.")
            }
            
            Section {
                HStack {
                    Text("Persistent Memory")
                    Spacer()
                    Button("Open File") {
                        NSWorkspace.shared.open(MemoryManager.shared.memoryFileURL)
                    }
                }
            } header: {
                Text("AI Memory")
            } footer: {
                Text("The AI uses this markdown file to remember things about you. You can edit it manually or ask the AI to update it.")
            }
        }
        .formStyle(.grouped)
    }
}

struct ProvidersSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var ollamaService = OllamaService()
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "sparkles").foregroundStyle(.purple).frame(width: 20)
                    APIKeyField(title: "Gemini API Key", text: $settings.geminiApiKey)
                }
                HStack {
                    Image(systemName: "o.square").foregroundStyle(.green).frame(width: 20)
                    APIKeyField(title: "OpenAI API Key", text: $settings.openaiApiKey)
                }
                HStack {
                    Image(systemName: "c.square").foregroundStyle(.orange).frame(width: 20)
                    APIKeyField(title: "Claude API Key", text: $settings.claudeApiKey)
                }
                HStack {
                    Image(systemName: "d.circle").foregroundStyle(.blue).frame(width: 20)
                    APIKeyField(title: "DeepSeek API Key", text: $settings.deepseekApiKey)
                }
            } header: {
                Text("API Authentication")
            } footer: {
                Text("Your keys are securely stored in the macOS Keychain.")
            }
            
            Section {
                HStack {
                    Image(systemName: "desktopcomputer").foregroundStyle(.cyan).frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ollama (Local)")
                            .font(.system(size: 13, weight: .medium))
                        HStack(spacing: 4) {
                            Circle()
                                .fill(ollamaService.isConnected ? .green : .red)
                                .frame(width: 6, height: 6)
                            Text(ollamaService.isConnected ? "Connected" : "Not connected")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await ollamaService.fetchAvailableModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Refresh connection")
                }
                
                HStack {
                    Text("Endpoint")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("http://localhost:11434", text: $settings.ollamaEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onChange(of: settings.ollamaEndpoint) { _, _ in
                            Task { await ollamaService.fetchAvailableModels() }
                        }
                }
                
                HStack {
                    Text("Model")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    if !ollamaService.availableModels.isEmpty {
                        Picker("", selection: $settings.ollamaModelName) {
                            Text("Select a model...").tag("")
                            ForEach(ollamaService.availableModels) { model in
                                HStack {
                                    Text(model.displayName)
                                    if model.supportsVision {
                                        Image(systemName: "eye.fill")
                                            .font(.system(size: 8))
                                    }
                                    Text(model.sizeLabel)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(model.name)
                            }
                        }
                        .labelsHidden()
                    } else {
                        TextField("Model name (e.g. llama3, mistral)", text: $settings.ollamaModelName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }
            } header: {
                Text("Local Model")
            } footer: {
                Text("Requires Ollama running locally. Install from ollama.com. No API key needed.")
            }
            
            Section {
                Picker("Active Provider", selection: $settings.activeProvider) {
                    if !settings.geminiApiKey.isEmpty { Label("Google Gemini", systemImage: "sparkles").tag(AIProvider.gemini) }
                    if !settings.openaiApiKey.isEmpty { Label("OpenAI", systemImage: "o.square").tag(AIProvider.openai) }
                    if !settings.claudeApiKey.isEmpty { Label("Anthropic Claude", systemImage: "c.square").tag(AIProvider.claude) }
                    if !settings.deepseekApiKey.isEmpty { Label("DeepSeek", systemImage: "d.circle").tag(AIProvider.deepseek) }
                    if !settings.ollamaModelName.isEmpty { Label("Ollama (Local)", systemImage: "desktopcomputer").tag(AIProvider.ollama) }
                    
                    if settings.geminiApiKey.isEmpty && settings.openaiApiKey.isEmpty && settings.claudeApiKey.isEmpty && settings.deepseekApiKey.isEmpty && settings.ollamaModelName.isEmpty {
                        Text("No provider configured").tag(AIProvider.gemini)
                    }
                }
                
                if settings.activeProvider != .ollama {
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
                        case .ollama:
                            EmptyView()
                        }
                    }
                }
            } header: {
                Text("Model Configuration")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task { await ollamaService.fetchAvailableModels() }
        }
    }
}

struct APIKeyField: View {
    let title: String
    @Binding var text: String
    @State private var isVisible = false
    
    var body: some View {
        HStack {
            if isVisible {
                TextField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField(title, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button(action: {
                isVisible.toggle()
            }) {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Personas Settings

struct PersonasSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var editingPersona: PersonaConfig?
    @State private var showNewPersona = false
    
    var body: some View {
        Form {
            Section {
                ForEach(Array(settings.personas.enumerated()), id: \.element.id) { index, persona in
                    HStack {
                        Image(systemName: persona.icon)
                            .font(.system(size: 14))
                            .frame(width: 24)
                            .foregroundStyle(settings.activePersonaIndex == index ? .purple : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(persona.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(persona.systemPrompt.prefix(60) + "...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if settings.activePersonaIndex == index {
                            Text("Active")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.purple.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        Button {
                            editingPersona = persona
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        
                        if settings.personas.count > 1 {
                            Button {
                                settings.personas.removeAll { $0.id == persona.id }
                                if settings.activePersonaIndex >= settings.personas.count {
                                    settings.activePersonaIndex = 0
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.activePersonaIndex = index
                    }
                }
            } header: {
                HStack {
                    Text("Custom Personas")
                    Spacer()
                    Button {
                        showNewPersona = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Personas define the AI's behavior and expertise. Click a persona to set it as active. Click the pencil icon to edit.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingPersona) { persona in
            PersonaEditorSheet(persona: persona) { updated in
                if let idx = settings.personas.firstIndex(where: { $0.id == updated.id }) {
                    settings.personas[idx] = updated
                }
                editingPersona = nil
            }
        }
        .sheet(isPresented: $showNewPersona) {
            PersonaEditorSheet(persona: PersonaConfig(name: "", icon: "star.fill", systemPrompt: "")) { newPersona in
                settings.personas.append(newPersona)
                showNewPersona = false
            }
        }
    }
}

struct PersonaEditorSheet: View {
    @State var persona: PersonaConfig
    let onSave: (PersonaConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let availableIcons = [
        "sparkles", "chevron.left.forwardslash.chevron.right", "pencil.and.outline",
        "brain.head.profile", "lightbulb.fill", "book.fill",
        "hammer.fill", "paintbrush.fill", "wand.and.stars",
        "star.fill", "heart.fill", "bolt.fill",
        "globe", "doc.text.fill", "terminal.fill"
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text(persona.name.isEmpty ? "New Persona" : "Edit Persona")
                .font(.system(size: 16, weight: .bold))
                .padding(.top, 8)
            
            TextField("Persona Name", text: $persona.name)
                .textFieldStyle(.roundedBorder)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32)), count: 8), spacing: 8) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            persona.icon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(persona.icon == icon ? Color.purple.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(persona.icon == icon ? Color.purple : Color.clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("System Prompt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $persona.systemPrompt)
                    .font(.system(size: 12))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Save") {
                    guard !persona.name.isEmpty else { return }
                    onSave(persona)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(persona.name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

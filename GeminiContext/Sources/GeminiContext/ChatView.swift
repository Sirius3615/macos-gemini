import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct EditorConfig: Identifiable {
    let id = UUID()
    let image: NSImage
    let onComplete: (Data?) -> Void
}

// MARK: - ChatView

struct ChatView: View {
    let screenshot: NSImage?
    let screenshotData: Data?
    let activeContext: ActiveWindowContext?
    let onDismiss: () -> Void
    var onResize: ((NSSize) -> Void)?
    var initiallyExpanded: Bool = false
    var isRegularWindow: Bool = false

    @StateObject private var geminiService = GeminiService()
    @StateObject private var ollamaService = OllamaService()
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var history = ChatHistoryManager.shared
    @ObservedObject private var floatingPanelManager = FloatingPanelManager.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var isScreenshotExpanded = true
    @State private var showModelPicker = false
    @State private var apiKeyInput = ""
    @State private var errorMessage: String?
    @State private var currentSessionId: UUID?
    @State private var isExpanded = false
    @FocusState private var isInputFocused: Bool
    @FocusState private var isSearchFocused: Bool

    @State private var showSidebar = false
    @State private var showContextSidebar = true
    @State private var searchText = ""
    @State private var screenshotCleared = false
    @State private var selectedContextId: String?
    @FocusState private var focusedContextId: String?
    
    // Smart image gating state
    @State private var screenshotSentThisSession: Bool = false
    @State private var screenshotForceIncluded: Bool = false
    
    // File drop support
    @State private var attachments: [ChatAttachment] = []
    @State private var isTargeted = false
    
    /// Whether the active service is currently generating
    private var isActiveServiceGenerating: Bool {
        settings.activeProvider == .ollama ? ollamaService.isGenerating : geminiService.isGenerating
    }
    
    /// Status message from the active service
    private var activeStatusMessage: String? {
        settings.activeProvider == .ollama ? ollamaService.statusMessage : geminiService.statusMessage
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                compactPillView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                if isRegularWindow {
                    Color(red: 0.05, green: 0.05, blue: 0.08)
                        .ignoresSafeArea()
                    LiquidBlobsView()
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                        .ignoresSafeArea()
                } else {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isRegularWindow ? 12 : (isExpanded ? 16 : 36)))
        .overlay(
            RoundedRectangle(cornerRadius: isRegularWindow ? 12 : (isExpanded ? 16 : 36))
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(isRegularWindow ? 0.18 : 0.4), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .onAppear { 
            geminiService.selectedModel = settings.selectedModel
            if let lastSession = history.sessions.first {
                loadSession(lastSession)
            } else {
                currentSessionId = UUID()
                screenshotCleared = false
            }
            
            // Integrate accumulated recent screenshots from FloatingPanelManager
            let recentCaptures = floatingPanelManager.recentCaptures
            if recentCaptures.count > 1 {
                // If there are multiple captures in the last minute, use the latest one as the main screenshot
                // and add the previous ones as attachments to the current session context.
                // Or simply add *all* additional ones as attachments so they can be managed.
                
                // Sort chronologically (oldest first) or leave as is (newest last)
                // We'll set the newest as the main screenshot (if not cleared)
                // and the rest as image attachments.
                
                let previousCaptures = recentCaptures.dropLast()
                
                for capture in previousCaptures {
                    let name = "Screenshot \(Int(capture.timestamp.timeIntervalSince1970)).jpg"
                    if !attachments.contains(where: { $0.name == name }) {
                        let currentImageCount = (activeScreenshotData != nil ? 1 : 0) + attachments.filter { $0.mimeType.starts(with: "image/") }.count
                        if currentImageCount < 10 {
                            attachments.append(ChatAttachment(
                                name: name,
                                data: capture.data,
                                mimeType: "image/jpeg"
                            ))
                        }
                    } else if let attIndex = attachments.firstIndex(where: { $0.name == name }) {
                        // ensure it has latest potentially edited data
                        attachments[attIndex] = ChatAttachment(
                            id: attachments[attIndex].id,
                            name: name,
                            data: capture.data,
                            mimeType: "image/jpeg"
                        )
                    }
                }
            }

            // Always set the newly captured screenshot as the active context
            if let newScreenshot = screenshotData {
                editedScreenshotData = newScreenshot
                screenshotCleared = false
            }
            
            // If opened via full chat shortcut, expand immediately
            if initiallyExpanded {
                isExpanded = true
                onResize?(NSSize(width: 700, height: 600))
            }
            
            // Auto focus the input field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .sheet(item: $editorConfig) { config in
            ScreenshotEditorView(originalImage: config.image) { data in
                config.onComplete(data)
                self.editorConfig = nil
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard isExpanded else { return false } // Only allow file drops in regular (full) chat mode
            let group = DispatchGroup()
            var urlsToLoad: [URL] = []
            
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                        defer { group.leave() }
                        if let data = data as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urlsToLoad.append(url)
                        } else if let url = data as? URL {
                            urlsToLoad.append(url)
                        }
                    }
                }
            }
            
            group.notify(queue: .main) {
                for url in urlsToLoad {
                    self.addFile(url: url)
                }
            }
            return true
        }
        .overlay {
            if isTargeted && isExpanded {
                ZStack {
                    VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .scaleEffect(isTargeted ? 1.1 : 1.0)
                        
                        Text("Drop files to attach to chat")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("Supports images, PDFs, text, and code files")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(30)
                    .background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 4])
                            )
                    )
                }
                .transition(.opacity)
            }
        }
    }
    
    private var expandedView: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebarView
                    .frame(width: 200)
                    .transition(.move(edge: .leading))
                
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }
            
            VStack(spacing: 0) {
                titleBar
                
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                
                if !settings.hasAPIKey {
                    apiKeySetupView
                } else {
                    chatArea
                    inputBar
                }
            }
            .frame(minWidth: 400, minHeight: 400)
            
            if showContextSidebar {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                
                contextSidebarView
                    .frame(width: 200)
                    .transition(.move(edge: .trailing))
            }
        }
    }
    
    private var compactPillView: some View {
        HStack(spacing: 12) {
            // Squircle image on the left
            if let img = activeScreenshotImage, let original = screenshot {
                Button {
                    editorConfig = EditorConfig(image: original) { data in
                        if let d = data {
                            self.editedScreenshotData = d
                            if var last = floatingPanelManager.recentCaptures.last, let newImg = NSImage(data: d) {
                                let updated = RecentCapture(image: newImg, data: d, timestamp: last.timestamp)
                                floatingPanelManager.recentCaptures[floatingPanelManager.recentCaptures.count - 1] = updated
                            }
                        }
                    }
                } label: {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1))
                        .shadow(radius: 2)
                        .overlay(
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .opacity(0.8)
                        )
                }
                .buttonStyle(.plain)
            } else {
                // Placeholder squircle if no image
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            
            Button(action: {
                onDismiss() // Dismiss the floating panel
                ChatWindowManager.shared.openRegularChatWindow(
                    screenshot: screenshot,
                    screenshotData: screenshotData,
                    activeContext: activeContext
                )
            }) {
                Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            TextField("Ask about anything...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isInputFocused)
                .padding(.horizontal, 4)
                .onSubmit { expandAndSendMessage() }
            
            Button(action: expandAndSendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty 
                                     ? AnyShapeStyle(.secondary.opacity(0.5)) 
                                     : AnyShapeStyle(.primary))
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func expandAndSendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isExpanded = true
        onResize?(NSSize(width: 700, height: 600))
        
        // Give the window a short moment to animate its frame before generating text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sendMessage()
        }
    }

    private var filteredSessions: [ChatSession] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return history.sessions
        }
        let query = searchText.lowercased()
        return history.sessions.filter { session in
            session.title.lowercased().contains(query) ||
            session.messages.contains { $0.content.lowercased().contains(query) }
        }
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chat History")
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.top, isRegularWindow ? 42 : 16) // Extra padding to avoid macOS traffic light controls
                .padding(.bottom, 8)
                
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(isSearchFocused ? 0.35 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSearchFocused 
                            ? AnyShapeStyle(LinearGradient(colors: [.purple.opacity(0.5), .blue.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.06)),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredSessions) { session in
                        Button(action: { loadSession(session) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text(session.timestamp, style: .date)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                currentSessionId == session.id 
                                ? AnyView(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                  )
                                : AnyView(Color.clear)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color.black.opacity(0.2))
    }
    
    private func loadSession(_ session: ChatSession) {
        currentSessionId = session.id
        messages = session.messages
        editedScreenshotData = session.screenshotData
        attachments = session.attachments ?? []
        screenshotCleared = (session.screenshotData == nil)
        selectedContextId = nil
    }

    // MARK: Title Bar
    private var titleBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // Window controls & Sidebar toggle
            HStack(spacing: 12) {
                if !isRegularWindow {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: { showSidebar.toggle() }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, (isRegularWindow && !showSidebar) ? 68 : 0) // Leaves safety space for traffic light window controls
            
            Spacer()
            
            VStack(spacing: 6) {
                Button(action: { showModelPicker.toggle() }) {
                    HStack(spacing: 5) {
                        if settings.activeProvider == .ollama {
                            Image(systemName: "desktopcomputer").font(.system(size: 11, weight: .semibold)).foregroundStyle(.cyan)
                            Text(settings.ollamaModelName.isEmpty ? "Ollama" : settings.ollamaModelName).font(.system(size: 12, weight: .medium))
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.purple)
                            Text(settings.selectedModel.displayName).font(.system(size: 12, weight: .medium))
                        }
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showModelPicker, arrowEdge: .bottom) { modelPicker }
                
                // Persona indicator
                Button {
                    let next = (settings.activePersonaIndex + 1) % settings.personas.count
                    settings.activePersonaIndex = next
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: settings.activePersona.icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                        Text(settings.activePersona.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Click to switch persona")
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button {
                    floatingPanelManager.isPinned.toggle()
                } label: {
                    Image(systemName: floatingPanelManager.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 16))
                        .foregroundStyle(floatingPanelManager.isPinned ? .white : .secondary)
                }
                .buttonStyle(.plain)
                .help(floatingPanelManager.isPinned ? "Unpin Window" : "Pin Window")
                
                Button(action: clearConversation) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Chat")
                
                Button(action: { showContextSidebar.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Toggle Context Sidebar")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.horizontal, 12).padding(.top, 8)
            if settings.activeProvider == .ollama {
                // Ollama: show the configured model name
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.ollamaModelName.isEmpty ? "No model configured" : settings.ollamaModelName)
                            .font(.system(size: 13, weight: .medium))
                        Text("Local · Ollama")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.cyan)
                }.padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                ForEach(GeminiModel.allCases) { model in
                    Button {
                        settings.selectedModel = model; geminiService.selectedModel = model; showModelPicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName).font(.system(size: 13, weight: .medium))
                                Text(model.description).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.selectedModel == model {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.purple)
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.vertical, 4).frame(width: 220)
    }

    // MARK: API Key Setup
    private var apiKeySetupView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "key.fill").font(.system(size: 36))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Gemini API Key Required").font(.system(size: 16, weight: .semibold))
            Text("Get your free API key from\nGoogle AI Studio").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: 10) {
                SecureField("Paste your API key...", text: $apiKeyInput)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .frame(maxWidth: 300).onSubmit { saveAPIKey() }
                Button(action: saveAPIKey) {
                    Text("Save & Connect").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                        .background(.linearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(apiKeyInput.isEmpty)
                Button("Get API Key →") { NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/apikey")!) }
                    .font(.system(size: 12)).foregroundStyle(.blue).buttonStyle(.plain)
            }
            Spacer()
        }.frame(maxWidth: .infinity).padding(20)
    }

    // MARK: Screenshot
    @State private var editorConfig: EditorConfig? {
        didSet { floatingPanelManager.isScreenshotEditorOpen = editorConfig != nil }
    }
    @State private var editedScreenshotData: Data?

    private var activeScreenshotData: Data? {
        if screenshotCleared { return nil }
        return editedScreenshotData ?? screenshotData
    }

    private var activeScreenshotImage: NSImage? {
        if screenshotCleared { return nil }
        if let data = editedScreenshotData, let img = NSImage(data: data) {
            return img
        }
        return screenshot
    }

    private var contextSidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Context")
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    if !screenshotCleared, let img = activeScreenshotImage, let original = screenshot {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    editorConfig = EditorConfig(image: original) { data in
                                        if let d = data {
                                            self.editedScreenshotData = d
                                            if var last = floatingPanelManager.recentCaptures.last, let newImg = NSImage(data: d) {
                                                let updated = RecentCapture(image: newImg, data: d, timestamp: last.timestamp)
                                                floatingPanelManager.recentCaptures[floatingPanelManager.recentCaptures.count - 1] = updated
                                            }
                                        }
                                    }
                                } label: {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .frame(maxWidth: .infinity)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    selectedContextId == "screenshot" 
                                                    ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    : AnyShapeStyle(Color.white.opacity(0.1)),
                                                    lineWidth: 2
                                                )
                                        )
                                        .overlay(
                                            Image(systemName: "pencil.circle.fill")
                                                .font(.system(size: 24))
                                                .foregroundStyle(.white, .black.opacity(0.5))
                                                .opacity(0.8)
                                        )
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    screenshotCleared = true
                                    editedScreenshotData = nil
                                    if selectedContextId == "screenshot" { selectedContextId = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .background(Circle().fill(.white).opacity(0.2))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                            
                            Text("Screenshot")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .focusable()
                        .focused($focusedContextId, equals: "screenshot")
                        .onTapGesture {
                            selectedContextId = "screenshot"
                            focusedContextId = "screenshot"
                        }
                        .onDeleteCommand {
                            if selectedContextId == "screenshot" {
                                screenshotCleared = true
                                editedScreenshotData = nil
                                selectedContextId = nil
                            }
                        }
                    }
                    
                    ForEach(attachments) { attachment in
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                if attachment.mimeType.starts(with: "image/"), let img = NSImage(data: attachment.data) {
                                    Button {
                                        editorConfig = EditorConfig(image: img) { data in
                                            if let d = data {
                                                if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                                    attachments[index] = ChatAttachment(id: attachment.id, name: attachment.name, data: d, mimeType: attachment.mimeType)
                                                    
                                                    // Also update in recentCaptures if it corresponds to one
                                                    if let rcIndex = floatingPanelManager.recentCaptures.firstIndex(where: { $0.data == attachment.data }), let newImg = NSImage(data: d) {
                                                        let old = floatingPanelManager.recentCaptures[rcIndex]
                                                        floatingPanelManager.recentCaptures[rcIndex] = RecentCapture(image: newImg, data: d, timestamp: old.timestamp)
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        attachmentIcon(for: attachment)
                                            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 120)
                                            .background(.white.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        selectedContextId == attachment.id.uuidString 
                                                        ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                        : AnyShapeStyle(Color.white.opacity(0.1)),
                                                        lineWidth: 2
                                                    )
                                            )
                                            .overlay(
                                                Image(systemName: "pencil.circle.fill")
                                                    .font(.system(size: 24))
                                                    .foregroundStyle(.white, .black.opacity(0.5))
                                                    .opacity(0.8)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    attachmentIcon(for: attachment)
                                        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 120)
                                        .background(.white.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(
                                                    selectedContextId == attachment.id.uuidString 
                                                    ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    : AnyShapeStyle(Color.white.opacity(0.1)),
                                                    lineWidth: 2
                                                )
                                        )
                                }
                                
                                Button {
                                    attachments.removeAll { $0.id == attachment.id }
                                    if selectedContextId == attachment.id.uuidString { selectedContextId = nil }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white, .gray)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                            }
                            Text(attachment.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .focusable()
                        .focused($focusedContextId, equals: attachment.id.uuidString)
                        .onTapGesture {
                            selectedContextId = attachment.id.uuidString
                            focusedContextId = attachment.id.uuidString
                        }
                        .onDeleteCommand {
                            if selectedContextId == attachment.id.uuidString {
                                attachments.removeAll { $0.id == attachment.id }
                                selectedContextId = nil
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(Color.black.opacity(0.2))
    }

    // MARK: Chat Area
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty && !isActiveServiceGenerating { emptyState }
                    ForEach(messages) { msg in MessageBubble(message: msg).id(msg.id) }
                    if isActiveServiceGenerating && !streamingText.isEmpty {
                        StreamingBubble(text: streamingText).id("streaming")
                    }
                    if let status = activeStatusMessage {
                        StatusBubble(message: status).id("status")
                    }
                    if isActiveServiceGenerating && streamingText.isEmpty && activeStatusMessage == nil {
                        TypingIndicator().id("typing")
                    }
                    if let err = errorMessage { ErrorBubble(message: err).id("error") }
                }.padding(14)
            }
            .onChange(of: streamingText) { _, _ in
                if isActiveServiceGenerating { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("streaming", anchor: .bottom) } }
            }
            .onChange(of: geminiService.statusMessage) { _, newValue in
                if newValue != nil {
                    withAnimation { proxy.scrollTo("status", anchor: .bottom) }
                }
            }
            .onChange(of: ollamaService.statusMessage) { _, newValue in
                if newValue != nil {
                    withAnimation { proxy.scrollTo("status", anchor: .bottom) }
                }
            }
            .onChange(of: messages.count) { _, _ in
                if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .onChange(of: isActiveServiceGenerating) { _, isGen in
                // Keep the chat panel pinned while the agent is running autonomously
                floatingPanelManager.isPinned = isGen
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CancelAgentGeneration"))) { _ in
                // Stop agent generation globally
                if settings.activeProvider == .ollama {
                    ollamaService.cancelGeneration()
                } else {
                    geminiService.cancelGeneration()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 32))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Ask about anything").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            Text(screenshot != nil ? "I can see your screen — ask me anything" : "Shake your mouse to capture context")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    // MARK: Input Bar
    private var inputBar: some View {
        VStack(spacing: 0) {
            // Active context chip
            if let ctx = activeContext, !ctx.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                    if !ctx.appName.isEmpty {
                        Text(ctx.appName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    if !ctx.selectedText.isEmpty {
                        Text("· \(ctx.selectedText.prefix(40))...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !ctx.activeURL.isEmpty {
                        Text("· \(ctx.activeURL.prefix(40))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(.blue.opacity(0.06))
                Divider().opacity(0.2)
            }
            
            HStack(spacing: 12) {
                Button(action: openFilePicker) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.white.opacity(0.04))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                TextField("Ask anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isInputFocused)
                    .onSubmit(sendMessage)
                
                // Token estimation label
                if !inputText.isEmpty {
                    Text(tokenEstimateLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                if isActiveServiceGenerating {
                    Button(action: {
                        if settings.activeProvider == .ollama {
                            ollamaService.cancelGeneration()
                        } else {
                            geminiService.cancelGeneration()
                        }
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.red.opacity(0.8))
                            .clipShape(Circle())
                            .shadow(color: .red.opacity(0.4), radius: 4)
                    }.buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.4) : .white)
                            .frame(width: 26, height: 26)
                            .background(
                                LinearGradient(
                                    colors: inputText.trimmingCharacters(in: .whitespaces).isEmpty 
                                        ? [.white.opacity(0.1), .white.opacity(0.05)]
                                        : [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .clear : .purple.opacity(0.4), radius: 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(isInputFocused ? 0.35 : 0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: isInputFocused 
                                ? [.purple.opacity(0.6), .blue.opacity(0.4)]
                                : [.white.opacity(0.08), .white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: isInputFocused ? .purple.opacity(0.15) : .clear, radius: 8)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
    
    private var tokenEstimateLabel: String {
        let count = GeminiService.estimateTokenCount(
            text: inputText,
            imageData: activeScreenshotData,
            attachments: attachments,
            activeContext: activeContext?.contextDescription,
            conversationHistory: messages
        )
        if count >= 1000 {
            return String(format: "~%.1fk", Double(count) / 1000.0)
        }
        return "~\(count)"
    }
    
    private func attachmentIcon(for attachment: ChatAttachment) -> some View {
        if attachment.mimeType.starts(with: "image/") {
            if let img = NSImage(data: attachment.data) {
                return AnyView(Image(nsImage: img).resizable().aspectRatio(contentMode: .fill))
            }
        }
        
        let icon: String
        if attachment.mimeType == "application/pdf" {
            icon = "doc.text.fill"
        } else if attachment.mimeType.starts(with: "text/") {
            icon = "doc.plaintext.fill"
        } else {
            icon = "doc.fill"
        }
        
        return AnyView(Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.secondary))
    }

    // MARK: Actions
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        if let lastMessage = messages.last, Date().timeIntervalSince(lastMessage.timestamp) > settings.chatResetMinutes * 60 {
            clearConversation()
        }
        
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""; streamingText = ""
        if currentSessionId == nil {
            currentSessionId = UUID()
        }
        
        // Save initial state
        saveCurrentSession()
        
        // Determine image data based on smart gating
        let effectiveImageData: Data?
        let deferredImageData: Data?
        
        if settings.smartImageGating && !screenshotSentThisSession && !screenshotForceIncluded {
            // Smart gating: defer the screenshot, let the AI decide
            effectiveImageData = nil
            deferredImageData = activeScreenshotData
        } else {
            // Either gating is off, screenshot was already sent, or user force-included
            effectiveImageData = activeScreenshotData
            deferredImageData = nil
        }
        
        let completionHandler: @MainActor (Result<String, Error>) -> Void = { result in
            switch result {
            case .success(let full): 
                messages.append(ChatMessage(role: .assistant, content: full))
                streamingText = ""
                
                // Mark screenshot as sent if it was used (either directly or via tool)
                if effectiveImageData != nil || deferredImageData != nil {
                    screenshotSentThisSession = true
                }
                
                var imageCount = activeScreenshotData != nil ? 1 : 0
                var nextAttachments = [ChatAttachment]()
                for attachment in attachments.reversed() {
                    if attachment.mimeType.starts(with: "image/") {
                        if imageCount < 10 {
                            nextAttachments.insert(attachment, at: 0)
                            imageCount += 1
                        }
                    } else {
                        nextAttachments.insert(attachment, at: 0)
                    }
                }
                attachments = nextAttachments
                
                saveCurrentSession()
            case .failure(let err): 
                errorMessage = err.localizedDescription
                streamingText = ""
            }
        }
        
        if settings.activeProvider == .ollama {
            ollamaService.streamGenerate(
                prompt: text, imageData: effectiveImageData,
                attachments: attachments,
                activeContextText: activeContext?.contextDescription,
                conversationHistory: Array(messages.dropLast()),
                deferredImageData: deferredImageData,
                onToken: { streamingText += $0 },
                onComplete: completionHandler
            )
        } else {
            geminiService.streamGenerate(
                prompt: text, imageData: effectiveImageData,
                attachments: attachments,
                activeContextText: activeContext?.contextDescription,
                conversationHistory: Array(messages.dropLast()),
                deferredImageData: deferredImageData,
                onToken: { streamingText += $0 },
                onComplete: completionHandler
            )
        }
    }
    
    private func saveCurrentSession() {
        guard let id = currentSessionId, !messages.isEmpty else { return }
        let title = messages.first?.content.prefix(30).trimmingCharacters(in: .whitespaces) ?? "New Chat"
        let session = ChatSession(
            id: id,
            title: String(title) + (title.count == 30 ? "..." : ""),
            messages: messages,
            timestamp: Date(),
            screenshotData: activeScreenshotData,
            attachments: attachments
        )
        history.saveSession(session)
    }

    private func saveAPIKey() {
        let k = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines); guard !k.isEmpty else { return }
        switch settings.activeProvider {
        case .gemini: settings.geminiApiKey = k
        case .openai: settings.openaiApiKey = k
        case .claude: settings.claudeApiKey = k
        case .deepseek: settings.deepseekApiKey = k
        case .ollama: break // Ollama doesn't use API keys
        }
        apiKeyInput = ""
    }
    private func clearConversation() {
        geminiService.cancelGeneration()
        ollamaService.cancelGeneration()
        messages.removeAll()
        attachments.removeAll()
        streamingText = ""
        errorMessage = nil
        currentSessionId = UUID()
        screenshotCleared = false
        editedScreenshotData = screenshotData
        selectedContextId = nil
        screenshotSentThisSession = false
        screenshotForceIncluded = false
    }
    
    // MARK: File Handling
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        // Guard against auto-dismiss while file picker is open
        floatingPanelManager.isFilePickerOpen = true
        
        // Bring app to front so panel isn't behind other apps
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = NSApp.windows.first(where: { $0.isKeyWindow || $0.isMainWindow }) {
            panel.beginSheetModal(for: window) { response in
                if response == .OK {
                    for url in panel.urls {
                        self.addFile(url: url)
                    }
                }
                // Allow auto-dismiss again
                self.floatingPanelManager.isFilePickerOpen = false
            }
        } else {
            panel.level = .modalPanel
            if panel.runModal() == .OK {
                for url in panel.urls {
                    addFile(url: url)
                }
            }
            // Allow auto-dismiss again
            floatingPanelManager.isFilePickerOpen = false
        }
    }
    
    private func addFile(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent
        let mimeType = getMimeType(for: url)
        
        let isImage = mimeType.starts(with: "image/")
        if isImage {
            let currentImageCount = (activeScreenshotData != nil ? 1 : 0) + attachments.filter { $0.mimeType.starts(with: "image/") }.count
            if currentImageCount >= 10 {
                errorMessage = "Maximum of 10 images allowed at once."
                return
            }
        }
        
        withAnimation {
            attachments.append(ChatAttachment(name: name, data: data, mimeType: mimeType))
        }
    }
    
    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt", "swift", "js", "ts", "py", "html", "css", "json", "md": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Models

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    let role: Role
    let content: String
    var timestamp = Date()
    
    enum Role: String, Codable, Equatable { 
        case user, assistant 
    }
}

// MARK: - Custom WKWebView Subclass
/// Prevents the WKWebView from trapping vertical scroll events, handing them over to the SwiftUI ScrollView
class ChatWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // If there's more horizontal scrolling (like swiping a code block), let the web view handle it natively
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event)
        } else {
            // Forward vertical scrolling up the responder chain (to the parent SwiftUI ScrollView)
            self.nextResponder?.scrollWheel(with: event)
        }
    }
}

// MARK: - MarkdownWebView (WKWebView-based rich renderer)

/// Renders Markdown with syntax-highlighted code blocks (highlight.js) and
/// LaTeX math (KaTeX) inside a WKWebView. Auto-resizes to fit content.
struct MarkdownWebView: NSViewRepresentable {
    let text: String
    
    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "resize")
        contentController.add(context.coordinator, name: "copyCode")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        
        // Initialize our custom subclass instead of the default WKWebView
        let wv = ChatWKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 20), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv
        return wv
    }
    
    func updateNSView(_ wv: WKWebView, context: Context) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        
        let html = Self.buildHTML(markdownContent: escaped)
        
        // Only reload if content changed
        if context.coordinator.lastText != text {
            context.coordinator.lastText = text
            wv.loadHTMLString(html, baseURL: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var lastText: String?
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "resize", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    guard let wv = self.webView else { return }
                    let newHeight = max(height + 2, 20)
                    if let constraint = wv.constraints.first(where: { $0.firstAttribute == .height }) {
                        constraint.constant = newHeight
                    } else {
                        let c = wv.heightAnchor.constraint(equalToConstant: newHeight)
                        c.priority = .defaultHigh
                        c.isActive = true
                    }
                    wv.invalidateIntrinsicContentSize()
                }
            } else if message.name == "copyCode", let code = message.body as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Use documentElement.scrollHeight for a more accurate reading to prevent internal overflow constraints
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [weak self] result, _ in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        guard let wv = self?.webView else { return }
                        let newHeight = max(height + 2, 20)
                        if let constraint = wv.constraints.first(where: { $0.firstAttribute == .height }) {
                            constraint.constant = newHeight
                        } else {
                            let c = wv.heightAnchor.constraint(equalToConstant: newHeight)
                            c.priority = .defaultHigh
                            c.isActive = true
                        }
                        wv.invalidateIntrinsicContentSize()
                    }
                }
            }
        }
    }
    
    // MARK: - HTML Template
    
    private static func buildHTML(markdownContent: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github-dark.min.css">
        <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
        <script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
                /* Prevents any internal vertical scrolling and scrollbars in the WKWebView */
                overflow-y: hidden;
            }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
                font-size: 13px;
                line-height: 1.6;
                color: rgba(255,255,255,0.92);
                background: transparent;
                padding: 0;
                -webkit-font-smoothing: antialiased;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            p { margin-bottom: 8px; }
            p:last-child { margin-bottom: 0; }
            
            h1, h2, h3, h4, h5, h6 {
                color: rgba(255,255,255,0.95);
                font-weight: 600;
                margin-top: 12px;
                margin-bottom: 6px;
                line-height: 1.3;
            }
            h1 { font-size: 18px; }
            h2 { font-size: 16px; }
            h3 { font-size: 14px; }
            h4, h5, h6 { font-size: 13px; }
            h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
            
            strong { color: rgba(255,255,255,0.98); font-weight: 600; }
            em { font-style: italic; }
            
            a {
                color: #7aadff;
                text-decoration: none;
            }
            a:hover { text-decoration: underline; }
            
            code:not(pre code) {
                background: rgba(255,255,255,0.08);
                border: 1px solid rgba(255,255,255,0.1);
                border-radius: 4px;
                padding: 1px 5px;
                font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
                font-size: 11.5px;
                color: #e8b4f8;
            }
            
            pre {
                background: rgba(0,0,0,0.35);
                border: 1px solid rgba(255,255,255,0.08);
                border-radius: 8px;
                margin: 8px 0;
                overflow: hidden;
                position: relative;
            }
            pre code {
                display: block;
                padding: 12px 14px;
                font-family: 'SF Mono', Menlo, Monaco, 'Courier New', monospace;
                font-size: 11.5px;
                line-height: 1.5;
                overflow-x: auto;
                color: rgba(255,255,255,0.88);
                -webkit-overflow-scrolling: touch;
            }
            pre code.hljs { background: transparent; padding: 12px 14px; }
            
            .code-header {
                display: flex;
                align-items: center;
                justify-content: space-between;
                padding: 4px 10px;
                background: rgba(0,0,0,0.25);
                border-bottom: 1px solid rgba(255,255,255,0.06);
            }
            .code-lang {
                font-family: 'SF Mono', Menlo, monospace;
                font-size: 10px;
                color: rgba(255,255,255,0.4);
                text-transform: uppercase;
                letter-spacing: 0.5px;
            }
            .copy-btn {
                font-size: 10px;
                color: rgba(255,255,255,0.4);
                background: none;
                border: 1px solid rgba(255,255,255,0.1);
                border-radius: 4px;
                padding: 2px 8px;
                cursor: pointer;
                transition: all 0.15s;
            }
            .copy-btn:hover {
                color: rgba(255,255,255,0.7);
                border-color: rgba(255,255,255,0.2);
                background: rgba(255,255,255,0.05);
            }
            
            ul, ol {
                margin: 6px 0;
                padding-left: 20px;
            }
            li { margin-bottom: 3px; }
            li > ul, li > ol { margin: 2px 0; }
            
            blockquote {
                border-left: 3px solid rgba(130, 100, 255, 0.5);
                margin: 8px 0;
                padding: 4px 12px;
                color: rgba(255,255,255,0.7);
                background: rgba(130, 100, 255, 0.05);
                border-radius: 0 6px 6px 0;
            }
            
            table {
                border-collapse: collapse;
                margin: 8px 0;
                width: 100%;
                font-size: 12px;
            }
            th, td {
                border: 1px solid rgba(255,255,255,0.1);
                padding: 6px 10px;
                text-align: left;
            }
            th {
                background: rgba(255,255,255,0.05);
                font-weight: 600;
                color: rgba(255,255,255,0.8);
            }
            tr:nth-child(even) { background: rgba(255,255,255,0.02); }
            
            hr {
                border: none;
                border-top: 1px solid rgba(255,255,255,0.1);
                margin: 12px 0;
            }
            
            .katex-display {
                margin: 10px 0;
                overflow-x: auto;
                overflow-y: hidden;
                padding: 4px 0;
            }
            .katex { font-size: 1.05em; }
            
            img { max-width: 100%; border-radius: 6px; }
            
            ::selection { background: rgba(130, 100, 255, 0.35); }
        </style>
        </head>
        <body>
        <div id="content"></div>
        <script>
        (function() {
            // Configure marked
            marked.setOptions({
                gfm: true,
                breaks: false,
                smartypants: true
            });
            
            // Custom renderer for code blocks with copy button
            const renderer = new marked.Renderer();
            renderer.code = function(obj) {
                const code = typeof obj === 'object' ? obj.text : obj;
                const lang = typeof obj === 'object' ? obj.lang : arguments[1];
                let highlighted;
                try {
                    if (lang && hljs.getLanguage(lang)) {
                        highlighted = hljs.highlight(code, { language: lang }).value;
                    } else {
                        highlighted = hljs.highlightAuto(code).value;
                    }
                } catch(e) {
                    highlighted = code.replace(/</g, '&lt;').replace(/>/g, '&gt;');
                }
                const escapedCode = code.replace(/\\\\/g, '\\\\\\\\').replace(/'/g, "\\\\'").replace(/\\n/g, '\\\\n');
                const header = lang ? `<div class="code-header"><span class="code-lang">${lang}</span><button class="copy-btn" onclick="copyCode('${escapedCode}')">Copy</button></div>` : `<div class="code-header"><span class="code-lang"></span><button class="copy-btn" onclick="copyCode('${escapedCode}')">Copy</button></div>`;
                return `${header}<pre><code class="hljs ${lang || ''}">${highlighted}</code></pre>`;
            };
            marked.use({ renderer: renderer });
            
            // Process LaTeX before marked parses the markdown
            function processLaTeX(text) {
                // Display math: $$...$$
                text = text.replace(/\\$\\$([\\s\\S]*?)\\$\\$/g, function(match, expr) {
                    try {
                        return '<div class="katex-display">' + katex.renderToString(expr.trim(), {displayMode: true, throwOnError: false}) + '</div>';
                    } catch(e) { return match; }
                });
                // Inline math: $...$  (but not \\$ escaped)
                text = text.replace(/(?<!\\\\)\\$([^\\$\\n]+?)\\$/g, function(match, expr) {
                    try {
                        return katex.renderToString(expr.trim(), {displayMode: false, throwOnError: false});
                    } catch(e) { return match; }
                });
                return text;
            }
            
            function copyCode(code) {
                const decoded = code.replace(/\\\\n/g, '\\n').replace(/\\\\'/g, "'").replace(/\\\\\\\\/g, '\\\\');
                window.webkit.messageHandlers.copyCode.postMessage(decoded);
            }
            window.copyCode = copyCode;
            
            const raw = `\(markdownContent)`;
            const withLaTeX = processLaTeX(raw);
            document.getElementById('content').innerHTML = marked.parse(withLaTeX);
            
            // Notify height using documentElement for a more accurate read and consistent behavior
            setTimeout(function() {
                window.webkit.messageHandlers.resize.postMessage(document.documentElement.scrollHeight);
            }, 50);
            // Re-measure after fonts/images load
            setTimeout(function() {
                window.webkit.messageHandlers.resize.postMessage(document.documentElement.scrollHeight);
            }, 300);
        })();
        </script>
        </body>
        </html>
        """
    }
}


// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
                if isUser {
                    Text(message.content)
                        .font(.system(size: 13))
                        .lineSpacing(1.2 * 13 - 13) // Approximate line spacing for 1.2 line height
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 0.5))
                } else {
                    MarkdownWebView(text: message.content)
                }
            }
            
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                MarkdownWebView(text: text)
            }
            Spacer(minLength: 40)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(.purple.opacity(0.6)).frame(width: 6, height: 6)
                        .scaleEffect(phase == CGFloat(i) ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.vertical, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { phase = 2 }
    }
}

// MARK: - Error Bubble

struct ErrorBubble: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.orange)
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

// MARK: - StatusBubble

struct StatusBubble: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.purple)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.purple.opacity(0.24), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .scale))
    }
}

// MARK: - LiquidBlobsView

struct LiquidBlobsView: View {
    @State private var anim1 = false
    @State private var anim2 = false
    @State private var anim3 = false

    var body: some View {
        ZStack {
            // Blob 1: Purple
            RadialGradient(
                colors: [Color.purple.opacity(0.22), Color.clear],
                center: anim1 ? .topLeading : .center,
                startRadius: 10,
                endRadius: 350
            )
            .frame(width: 600, height: 600)
            .offset(x: anim1 ? -150 : -250, y: anim1 ? -100 : -200)
            
            // Blob 2: Indigo/Blue
            RadialGradient(
                colors: [Color.blue.opacity(0.18), Color.clear],
                center: anim2 ? .bottomTrailing : .center,
                startRadius: 10,
                endRadius: 400
            )
            .frame(width: 700, height: 700)
            .offset(x: anim2 ? 200 : 300, y: anim2 ? 150 : 250)
            
            // Blob 3: Cyan/Teal
            RadialGradient(
                colors: [Color.cyan.opacity(0.1), Color.clear],
                center: anim3 ? .topTrailing : .bottomLeading,
                startRadius: 10,
                endRadius: 300
            )
            .frame(width: 500, height: 500)
            .offset(x: anim3 ? 150 : 50, y: anim3 ? -200 : -100)
        }
        .blur(radius: 60)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                anim1.toggle()
            }
            withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
                anim2.toggle()
            }
            withAnimation(.easeInOut(duration: 9.0).repeatForever(autoreverses: true)) {
                anim3.toggle()
            }
        }
    }
}
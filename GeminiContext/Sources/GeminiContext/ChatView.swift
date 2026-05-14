import SwiftUI
import WebKit

// MARK: - ChatView

struct ChatView: View {
    let screenshot: NSImage?
    let screenshotData: Data?
    let onDismiss: () -> Void
    var onResize: ((NSSize) -> Void)?

    @StateObject private var geminiService = GeminiService()
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var history = ChatHistoryManager.shared
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

    @State private var showSidebar = false

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                compactPillView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 36))
        .overlay(RoundedRectangle(cornerRadius: isExpanded ? 16 : 36).stroke(.white.opacity(0.15), lineWidth: 1))
        .onAppear { 
            geminiService.selectedModel = settings.selectedModel
            if let lastSession = history.sessions.first {
                loadSession(lastSession)
            } else {
                currentSessionId = UUID()
            }
            // Always set the newly captured screenshot as the active context
            if let newScreenshot = screenshotData {
                editedScreenshotData = newScreenshot
            }
            
            // Auto focus the input field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        // Draggable window background
        .contentShape(Rectangle())
        .gesture(DragGesture().onChanged { _ in NSApp.keyWindow?.performDrag(with: NSApp.currentEvent!) })
    }
    
    private var expandedView: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebarView
                    .frame(width: 200)
                    .transition(.move(edge: .leading))
                Divider()
            }
            
            VStack(spacing: 0) {
                titleBar
                Divider().opacity(0.3)
                if !settings.hasAPIKey {
                    apiKeySetupView
                } else {
                    if screenshot != nil { screenshotSection }
                    chatArea
                    Divider().opacity(0.3)
                    inputBar
                }
            }
            .frame(minWidth: 400, minHeight: 400)
        }
    }
    
    private var compactPillView: some View {
        HStack(spacing: 12) {
            // Squircle image on the left
            if let img = activeScreenshotImage {
                Button {
                    showScreenshotEditor = true
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
                .sheet(isPresented: $showScreenshotEditor) {
                    ScreenshotEditorView(originalImage: screenshot!) { data in
                        if let d = data {
                            self.editedScreenshotData = d
                        }
                        self.showScreenshotEditor = false
                    }
                }
            } else {
                // Placeholder squircle if no image
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            
            TextField("Ask about your screen...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isInputFocused)
                .padding(.horizontal, 4)
                .onSubmit { expandAndSendMessage() }
            
            Button(action: expandAndSendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty 
                                     ? AnyShapeStyle(.white.opacity(0.2)) 
                                     : AnyShapeStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
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
        onResize?(NSSize(width: 480, height: 580))
        
        // Give the window a short moment to animate its frame before generating text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sendMessage()
        }
    }

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chat History")
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            
            Divider().opacity(0.5)
            
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(history.sessions) { session in
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
                            .background(currentSessionId == session.id ? Color.white.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color.black.opacity(0.15))
    }
    
    private func loadSession(_ session: ChatSession) {
        currentSessionId = session.id
        messages = session.messages
        editedScreenshotData = session.screenshotData
    }

    // MARK: Title Bar
    private var titleBar: some View {
        HStack(alignment: .top, spacing: 8) {
            // Window controls & Sidebar toggle
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                
                Button(action: { showSidebar.toggle() }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Button(action: { showModelPicker.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(.purple)
                    Text(settings.selectedModel.displayName).font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModelPicker, arrowEdge: .bottom) { modelPicker }
            
            Spacer()
            
            Button(action: clearConversation) {
                Image(systemName: "square.and.pencil").font(.system(size: 14)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).help("New Chat")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.horizontal, 12).padding(.top, 8)
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
                    .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
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
    @State private var showScreenshotEditor = false
    @State private var editedScreenshotData: Data?

    private var activeScreenshotData: Data? {
        editedScreenshotData ?? screenshotData
    }

    private var activeScreenshotImage: NSImage? {
        if let data = editedScreenshotData, let img = NSImage(data: data) {
            return img
        }
        return screenshot
    }

    private var screenshotSection: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { isScreenshotExpanded.toggle() } } label: {
                HStack {
                    Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Screen Context").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isScreenshotExpanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 14).padding(.vertical, 8)
            }.buttonStyle(.plain)
            
            if isScreenshotExpanded, let img = activeScreenshotImage {
                Button {
                    showScreenshotEditor = true
                } label: {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 14).padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .overlay(
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .opacity(0.8)
                        )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showScreenshotEditor) {
                    ScreenshotEditorView(originalImage: screenshot!) { data in
                        if let d = data {
                            self.editedScreenshotData = d
                        }
                        self.showScreenshotEditor = false
                    }
                }
            }
            Divider().opacity(0.3)
        }
    }

    // MARK: Chat Area
    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty && !geminiService.isGenerating { emptyState }
                    ForEach(messages) { msg in MessageBubble(message: msg).id(msg.id) }
                    if geminiService.isGenerating && !streamingText.isEmpty {
                        StreamingBubble(text: streamingText).id("streaming")
                    }
                    if geminiService.isGenerating && streamingText.isEmpty { TypingIndicator().id("typing") }
                    if let err = errorMessage { ErrorBubble(message: err).id("error") }
                }.padding(14)
            }
            .onChange(of: streamingText) { _, _ in
                if geminiService.isGenerating { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("streaming", anchor: .bottom) } }
            }
            .onChange(of: messages.count) { _, _ in
                if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 32))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("Ask about what's on screen").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            Text(screenshot != nil ? "I can see your screen — ask me anything" : "Shake your mouse to capture context")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    // MARK: Input Bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your screen...", text: $inputText)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($isInputFocused)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
                .onSubmit { sendMessage() }.disabled(geminiService.isGenerating)
            if geminiService.isGenerating {
                Button { geminiService.cancelGeneration() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 24)).foregroundStyle(.red.opacity(0.8))
                }.buttonStyle(.plain)
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(.white.opacity(0.2))
                            : AnyShapeStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }.buttonStyle(.plain).disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
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
        
        geminiService.streamGenerate(
            prompt: text, imageData: activeScreenshotData,
            conversationHistory: Array(messages.dropLast()),
            onToken: { streamingText += $0 },
            onComplete: { result in
                switch result {
                case .success(let full): 
                    messages.append(ChatMessage(role: .assistant, content: full))
                    streamingText = ""
                    saveCurrentSession()
                case .failure(let err): 
                    errorMessage = err.localizedDescription
                    streamingText = ""
                }
            }
        )
    }
    
    private func saveCurrentSession() {
        guard let id = currentSessionId, !messages.isEmpty else { return }
        let title = messages.first?.content.prefix(30).trimmingCharacters(in: .whitespaces) ?? "New Chat"
        let session = ChatSession(
            id: id,
            title: String(title) + (title.count == 30 ? "..." : ""),
            messages: messages,
            timestamp: Date(),
            screenshotData: activeScreenshotData
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
        }
        apiKeyInput = ""
    }
    private func clearConversation() {
        geminiService.cancelGeneration()
        messages.removeAll()
        streamingText = ""
        errorMessage = nil
        currentSessionId = UUID()
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

// MARK: - MarkdownTextView (Native)

/// Renders Markdown text using NSAttributedString with full support for
/// headers, bold, italic, code, links, lists, and LaTeX (via code blocks).
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let str):
                    Text(renderMarkdown(str))
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                case .codeBlock(let lang, let code):
                    CodeBlockView(language: lang, code: code)
                case .mathBlock(let expr):
                    MathBlockView(expression: expr)
                }
            }
        }
    }

    private func renderMarkdown(_ raw: String) -> AttributedString {
        // Convert inline $...$ LaTeX to code spans for visual distinction
        let processed = raw.replacingOccurrences(
            of: "\\$([^$]+)\\$",
            with: "`$1`",
            options: .regularExpression
        )
        if let attr = try? AttributedString(markdown: processed, options: .init(interpretedSyntax: .full)) {
            return attr
        }
        return AttributedString(raw)
    }

    // MARK: Block Parser
    enum Block { case markdown(String); case codeBlock(String?, String); case mathBlock(String) }

    private func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var current = ""
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                if !current.isEmpty { blocks.append(.markdown(current.trimmingCharacters(in: .whitespacesAndNewlines))); current = "" }
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code = ""
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    if !code.isEmpty { code += "\n" }
                    code += lines[i]; i += 1
                }
                if lang == "math" || lang == "latex" {
                    blocks.append(.mathBlock(code))
                } else {
                    blocks.append(.codeBlock(lang.isEmpty ? nil : lang, code))
                }
                i += 1; continue
            }
            // Check for display math $$...$$
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("$$") {
                if !current.isEmpty { blocks.append(.markdown(current.trimmingCharacters(in: .whitespacesAndNewlines))); current = "" }
                var math = line.replacingOccurrences(of: "$$", with: "")
                if math.contains("$$") { // single-line $$..$$
                    math = math.replacingOccurrences(of: "$$", with: "")
                    blocks.append(.mathBlock(math.trimmingCharacters(in: .whitespaces)))
                    i += 1; continue
                }
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    if l.trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                        math += "\n" + l.replacingOccurrences(of: "$$", with: "")
                        break
                    }
                    math += "\n" + l; i += 1
                }
                blocks.append(.mathBlock(math.trimmingCharacters(in: .whitespacesAndNewlines)))
                i += 1; continue
            }
            current += (current.isEmpty ? "" : "\n") + line
            i += 1
        }
        if !current.isEmpty { blocks.append(.markdown(current.trimmingCharacters(in: .whitespacesAndNewlines))) }
        return blocks
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = language {
                HStack {
                    Text(lang).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc").font(.system(size: 10))
                            Text("Copy").font(.system(size: 10))
                        }.foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }.padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.2))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 12, design: .monospaced)).foregroundStyle(.primary).textSelection(.enabled).padding(10)
            }
        }
        .background(Color(nsColor: .init(white: 0.08, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Math Block View (WKWebView + KaTeX)

struct MathBlockView: NSViewRepresentable {
    let expression: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.navigationDelegate = context.coordinator
        return wv
    }

    func updateNSView(_ wv: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html><html><head>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <style>
        body{margin:0;padding:8px;background:transparent;color:white;font-family:-apple-system;display:flex;justify-content:center;}
        .katex{font-size:1.1em;}
        </style></head><body>
        <div id="math"></div>
        <script>
        try{katex.render(String.raw`\(expression.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`"))`,
        document.getElementById('math'),{displayMode:true,throwOnError:false});}catch(e){document.getElementById('math').textContent=`\(expression)`;}
        document.body.style.height=document.body.scrollHeight+'px';
        window.webkit.messageHandlers.resize&&window.webkit.messageHandlers.resize.postMessage(document.body.scrollHeight);
        </script></body></html>
        """
        wv.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator: NSObject, WKNavigationDelegate {}
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
                    MarkdownTextView(text: message.content)
                        // MarkdownTextView should handle its own line spacing if possible,
                        // but we can apply it to the view container if it supports it.
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
                MarkdownTextView(text: text)
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

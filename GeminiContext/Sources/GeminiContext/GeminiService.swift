import Foundation
import AppKit

enum GeminiModel: String, CaseIterable, Identifiable {
    case proLatest = "gemini-pro-latest"
    case flashLatest = "gemini-flash-latest"
    case flashLiteLatest = "gemini-flash-lite-latest"
    case flash3Preview = "gemini-3-flash-preview"
    case pro31Preview = "gemini-3.1-pro-preview"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .proLatest: return "Gemini Pro Latest"
        case .flashLatest: return "Gemini Flash Latest"
        case .flashLiteLatest: return "Gemini Flash Lite Latest"
        case .flash3Preview: return "Gemini 3 Flash Preview"
        case .pro31Preview: return "Gemini 3.1 Pro Preview"
        }
    }

    var description: String {
        switch self {
        case .proLatest: return "Capable & versatile"
        case .flashLatest: return "Fast & efficient"
        case .flashLiteLatest: return "Ultra fast & lightweight"
        case .flash3Preview: return "Next-gen speed"
        case .pro31Preview: return "Next-gen capable"
        }
    }
}

/// Represents a file attachment in the chat (screenshot, dropped image, PDF, or code file).
struct ChatAttachment: Identifiable, Equatable, Codable {
    var id = UUID()
    let name: String
    let data: Data
    let mimeType: String
}

// MARK: - Gemini Type-Safe API Structs

struct GeminiPart: Codable {
    let text: String?
    let inlineData: InlineData?
    let functionCall: FunctionCall?
    let functionResponse: FunctionResponse?
    var thoughtSignature: String? = nil
    
    enum CodingKeys: String, CodingKey {
        case text
        case inlineData = "inline_data"
        case functionCall
        case functionResponse
        case thoughtSignature = "thoughtSignature"
    }
}

struct InlineData: Codable {
    let mimeType: String
    let data: String // Base64 encoded
    
    enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case data
    }
}

struct FunctionCall: Codable, Equatable {
    let name: String
    let args: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case name
        case args
    }
}

struct FunctionResponse: Codable {
    let name: String
    let response: [String: String]
}

struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

// MARK: - GeminiService

/// Direct REST API client for Gemini with streaming SSE support and Function Calling (Tools).
/// No Firebase dependency — uses raw URLSession against generativelanguage.googleapis.com.
final class GeminiService: ObservableObject {

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    @Published var selectedModel: GeminiModel = .pro31Preview
    @Published var isGenerating: Bool = false
    @Published var statusMessage: String? = nil

    /// Current streaming task (for cancellation).
    private var currentTask: Task<Void, Never>?
    private let toolExecutor = LocalToolExecutor.shared

    // MARK: - Streaming Generation

    /// Sends a message with optional image context and streams the response token-by-token.
    /// Supports recursive tool execution (autonomous file search and file reading).
    func streamGenerate(
        prompt: String,
        imageData: Data?,
        attachments: [ChatAttachment] = [],
        activeContextText: String? = nil,
        conversationHistory: [ChatMessage],
        deferredImageData: Data? = nil,
        onToken: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        // Cancel any in-progress generation
        cancelGeneration()

        let apiKey = SettingsManager.shared.activeAPIKey
        guard !apiKey.isEmpty else {
            Task { @MainActor in
                onComplete(.failure(GeminiError.noAPIKey))
            }
            return
        }

        isGenerating = true
        statusMessage = nil

        // Set deferred screenshot data for smart image gating
        if let deferred = deferredImageData {
            toolExecutor.deferredScreenshotData = deferred
        }

        currentTask = Task {
            // Reset overlay for this generation
            await MainActor.run {
                AgentOverlayManager.shared.resetForNewGeneration()
            }
            
            do {
                var toolExchange: [GeminiContent] = []
                var shouldContinue = true
                var fullText = ""
                var toolIterations = 0
                let maxToolIterations = 100
                // Track if screenshot was injected via the request_screenshot or take_screenshot tool
                var injectedScreenshotData: Data? = nil
                
                while shouldContinue {
                    try Task.checkCancellation()
                    
                    // Request current response (which may be a text chunk or a tool call)
                    let (text, functionCall, thoughtSig) = try await performStreamingRequest(
                        prompt: prompt,
                        imageData: imageData,
                        injectedScreenshotData: injectedScreenshotData,
                        attachments: attachments,
                        activeContextText: activeContextText,
                        conversationHistory: conversationHistory,
                        toolExchange: toolExchange,
                        apiKey: apiKey,
                        onToken: onToken
                    )
                    
                    fullText += text
                    
                    if let call = functionCall {
                        toolIterations += 1
                        
                        // Guard against infinite tool loops
                        if toolIterations > maxToolIterations {
                            fullText += "\n\n*[Stopped: reached the maximum of \(maxToolIterations) tool calls for this turn.]*"
                            shouldContinue = false
                            continue
                        }
                        
                        // Auto-update overlay BEFORE tool execution
                        let (icon, label) = self.toolDisplayInfo(call: call, iteration: toolIterations)
                        await MainActor.run {
                            AgentOverlayManager.shared.startTool(name: call.name, step: toolIterations, maxSteps: maxToolIterations)
                            self.statusMessage = "\(icon) \(label) (\(toolIterations)/\(maxToolIterations))"
                        }
                        
                        // Execute tool via shared LocalToolExecutor
                        let (result, screenshotData) = toolExecutor.execute(
                            toolName: call.name,
                            args: call.args
                        )
                        
                        // Auto-update overlay AFTER tool execution
                        await MainActor.run {
                            AgentOverlayManager.shared.endTool(icon: icon, label: label)
                        }
                        
                        // If screenshot was requested/taken and returned, inject it for the next request
                        if (call.name == "request_screenshot" || call.name == "take_screenshot"), let ssData = screenshotData {
                            injectedScreenshotData = ssData
                        }
                        
                        // Add tool call and response to the active exchange history
                        // Include thoughtSignature for Gemini 3 models
                        toolExchange.append(GeminiContent(
                            role: "model",
                            parts: [GeminiPart(text: nil, inlineData: nil, functionCall: call, functionResponse: nil, thoughtSignature: thoughtSig)]
                        ))
                        toolExchange.append(GeminiContent(
                            role: "user",
                            parts: [GeminiPart(text: nil, inlineData: nil, functionCall: nil, functionResponse: FunctionResponse(name: call.name, response: ["content": result]), thoughtSignature: nil)]
                        ))
                        
                        // Reset status message temporarily before invoking next turn
                        await MainActor.run {
                            self.statusMessage = nil
                        }
                    } else {
                        // No function call returned; we have the final model output
                        shouldContinue = false
                    }
                }
                
                await MainActor.run {
                    self.isGenerating = false
                    self.statusMessage = nil
                    AgentOverlayManager.shared.isVisible = false
                    onComplete(.success(fullText))
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.statusMessage = nil
                    AgentOverlayManager.shared.isVisible = false
                    if !(error is CancellationError) {
                        onComplete(.failure(error))
                    }
                }
            }
        }
    }

    /// Cancels any in-progress generation stream and associated tasks.
    func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
        statusMessage = nil
        AgentOverlayManager.shared.isVisible = false
    }

    // MARK: - Tool Display Helpers
    
    /// Returns a human-readable (icon, label) pair for a tool call.
    private func toolDisplayInfo(call: FunctionCall, iteration: Int) -> (String, String) {
        switch call.name {
        case "search_files":
            let query = call.args?["query"] ?? ""
            return ("🔍", "Searching for '\(query)'")
        case "read_file":
            let path = (call.args?["path"] ?? "").components(separatedBy: "/").last ?? ""
            return ("📖", "Reading \(path)")
        case "list_directory":
            let path = (call.args?["path"] ?? "").components(separatedBy: "/").suffix(2).joined(separator: "/")
            return ("📂", "Listing \(path)")
        case "get_calendar_events":
            return ("📅", "Checking calendar")
        case "request_screenshot":
            return ("📸", "Loading screenshot")
        case "take_screenshot":
            return ("📸", "Capturing screen")
        case "move_mouse":
            let x = call.args?["x"] ?? "?"
            let y = call.args?["y"] ?? "?"
            return ("🖱️", "Moving to \(x),\(y)")
        case "click_mouse":
            return ("👆", "Clicking")
        case "type_text":
            let text = call.args?["text"] ?? ""
            let preview = String(text.prefix(20))
            return ("⌨️", "Typing '\(preview)\(text.count > 20 ? "…" : "")'")
        case "execute_shell_command":
            let cmd = call.args?["command"] ?? ""
            let preview = String(cmd.prefix(30))
            return ("💻", "Running: \(preview)\(cmd.count > 30 ? "…" : "")")
        case "open_application":
            let app = call.args?["app_name"] ?? ""
            return ("🚀", "Opening \(app)")
        case "press_keys":
            let keys = call.args?["keys"] ?? ""
            return ("⌨️", "Pressing \(keys)")
        case "wait":
            let ms = call.args?["milliseconds"] ?? "1000"
            return ("⏳", "Waiting \(ms)ms")
        case "get_frontmost_app_info":
            return ("📱", "Checking active app")
        case "update_agent_status":
            return ("💭", "Updating status")
        case "read_memory":
            return ("🧠", "Reading memory")
        case "update_memory":
            return ("✍️", "Updating memory")
        default:
            return ("⚙️", "Running \(call.name)")
        }
    }

    // MARK: - Private: HTTP + SSE


    private func performStreamingRequest(
        prompt: String,
        imageData: Data?,
        injectedScreenshotData: Data?,
        attachments: [ChatAttachment],
        activeContextText: String?,
        conversationHistory: [ChatMessage],
        toolExchange: [GeminiContent],
        apiKey: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> (fullText: String, functionCall: FunctionCall?, thoughtSignature: String?) {

        let model = selectedModel.rawValue
        let urlString = "\(baseURL)/\(model):streamGenerateContent?alt=sse"

        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120

        // Build type-safe contents
        var contents: [GeminiContent] = []
        
        // 1. Add conversation history
        for message in conversationHistory {
            let role = message.role == .user ? "user" : "model"
            contents.append(GeminiContent(
                role: role,
                parts: [GeminiPart(text: message.content, inlineData: nil, functionCall: nil, functionResponse: nil)]
            ))
        }
        
        // 2. Build current turn user prompt
        var userParts: [GeminiPart] = []
        // Use injected screenshot (from request_screenshot tool) if available, otherwise use original
        let effectiveImageData = injectedScreenshotData ?? imageData
        if let imageData = effectiveImageData {
            userParts.append(GeminiPart(
                text: nil,
                inlineData: InlineData(mimeType: "image/jpeg", data: imageData.base64EncodedString()),
                functionCall: nil,
                functionResponse: nil
            ))
        }
        for attachment in attachments {
            userParts.append(GeminiPart(
                text: nil,
                inlineData: InlineData(mimeType: attachment.mimeType, data: attachment.data.base64EncodedString()),
                functionCall: nil,
                functionResponse: nil
            ))
        }
        
        var finalPrompt = prompt
        var contextParts: [String] = []
        if effectiveImageData != nil {
            contextParts.append("a screenshot of my current screen")
        }
        if !attachments.isEmpty {
            contextParts.append("\(attachments.count) attached file(s)")
        }
        if let activeContext = activeContextText, !activeContext.isEmpty {
            contextParts.append("context from my active window")
            finalPrompt = "Active window context:\n\(activeContext)\n\nUser question: \(prompt)"
        }
        
        if !contextParts.isEmpty && activeContextText == nil {
            finalPrompt = "Here is \(contextParts.joined(separator: " and ")). \(prompt)"
        } else if !contextParts.isEmpty && activeContextText != nil {
            let mediaContext = contextParts.filter { !$0.contains("active window") }
            if !mediaContext.isEmpty {
                finalPrompt = "Here is \(mediaContext.joined(separator: " and ")). \(finalPrompt)"
            }
        }
        
        userParts.append(GeminiPart(
            text: finalPrompt,
            inlineData: nil,
            functionCall: nil,
            functionResponse: nil
        ))
        
        contents.append(GeminiContent(role: "user", parts: userParts))
        
        // 3. Append the active tool exchange history (model calls and function responses)
        contents.append(contentsOf: toolExchange)

        // Build the request body dictionary
        var requestBody: [String: Any] = [
            "contents": try encodeToJSONArray(contents)
        ]

        // Add system instruction
        requestBody["systemInstruction"] = [
            "parts": [["text": SettingsManager.shared.systemPrompt]]
        ]

        // Generation config
        requestBody["generationConfig"] = [
            "temperature": 0.7,
            "topP": 0.95,
            "maxOutputTokens": 8192
        ]

        // Add tools for autonomous file access and capabilities
        requestBody["tools"] = [[
            "functionDeclarations": toolExecutor.toolDeclarations()
        ]]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Stream the response
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        var fullText = ""
        var pendingFunctionCall: FunctionCall? = nil
        var pendingThoughtSignature: String? = nil

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8) else { continue }

            if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {
                for candidate in chunk.candidates ?? [] {
                    for part in candidate.content?.parts ?? [] {
                        if let text = part.text {
                            fullText += text
                            await onToken(text)
                        }
                        if let call = part.functionCall {
                            pendingFunctionCall = call
                        }
                        // Capture thought_signature from the part
                        if let sig = part.thoughtSignature {
                            pendingThoughtSignature = sig
                        }
                    }
                }
            }
        }

        return (fullText, pendingFunctionCall, pendingThoughtSignature)
    }

    private func encodeToJSONArray<T: Encodable>(_ value: T) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(value)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GeminiError.invalidResponse
        }
        return array
    }


    // MARK: - Token Estimation
    
    /// Estimates the token count for the current context.
    /// Uses rough heuristics: ~4 chars per token for text, ~258 tokens per image tile.
    static func estimateTokenCount(
        text: String,
        imageData: Data?,
        attachments: [ChatAttachment],
        activeContext: String?,
        conversationHistory: [ChatMessage]
    ) -> Int {
        var tokens = 0
        
        // Text tokens (~4 chars per token)
        tokens += text.count / 4
        
        // Conversation history
        for msg in conversationHistory {
            tokens += msg.content.count / 4
        }
        
        // Active context
        if let ctx = activeContext {
            tokens += ctx.count / 4
        }
        
        // Image tokens (Gemini charges ~258 tokens per 256x256 tile)
        if let imgData = imageData {
            let imgSize = imgData.count
            let estimatedTiles = max(1, imgSize / 50_000)
            tokens += estimatedTiles * 258
        }
        
        // Attachment tokens
        for attachment in attachments {
            if attachment.mimeType.starts(with: "image/") {
                let estimatedTiles = max(1, attachment.data.count / 50_000)
                tokens += estimatedTiles * 258
            } else {
                tokens += attachment.data.count / 4
            }
        }
        
        // System prompt
        tokens += SettingsManager.shared.systemPrompt.count / 4
        
        return tokens
    }
}

// MARK: - Response Models

private struct StreamChunk: Codable {
    struct Candidate: Codable {
        struct Content: Codable {
            struct Part: Codable {
                let text: String?
                let functionCall: FunctionCall?
                let thoughtSignature: String?
                
                enum CodingKeys: String, CodingKey {
                    case text
                    case functionCall
                    case thoughtSignature = "thoughtSignature"
                }
            }
            let parts: [Part]?
            let role: String?
        }
        let content: Content?
        let finishReason: String?
    }
    let candidates: [Candidate]?
}

// MARK: - Errors

enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Add your Gemini API key in the menu bar settings."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from Gemini API."
        case .apiError(let code, let message):
            return "API Error (\(code)): \(message)"
        }
    }
}

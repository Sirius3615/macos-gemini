import Foundation
import AppKit

/// Represents an Ollama model from the `/api/tags` endpoint.
struct OllamaModelInfo: Identifiable, Equatable {
    let name: String
    let size: Int64
    let supportsVision: Bool

    var id: String { name }

    var displayName: String {
        // Prettify: "llama3:latest" → "Llama3"
        let base = name.components(separatedBy: ":").first ?? name
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    var sizeLabel: String {
        let gb = Double(size) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

/// AI service client for local Ollama models.
/// Uses Ollama's OpenAI-compatible `/v1/chat/completions` endpoint with streaming.
final class OllamaService: ObservableObject {

    @Published var isGenerating: Bool = false
    @Published var statusMessage: String? = nil
    @Published var availableModels: [OllamaModelInfo] = []
    @Published var isConnected: Bool = false

    /// Current streaming task (for cancellation).
    private var currentTask: Task<Void, Never>?

    private let toolExecutor = LocalToolExecutor.shared

    // MARK: - Model Discovery

    /// Fetches available models from Ollama's `/api/tags` endpoint.
    func fetchAvailableModels() async {
        let endpoint = SettingsManager.shared.ollamaEndpoint.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            await MainActor.run { isConnected = false }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run { isConnected = false; availableModels = [] }
                return
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {

                let visionKeywords = ["llava", "bakllava", "moondream", "minicpm-v", "llama3.2-vision"]

                let parsed: [OllamaModelInfo] = models.compactMap { model in
                    guard let name = model["name"] as? String else { return nil }
                    let size = model["size"] as? Int64 ?? 0
                    let hasVision = visionKeywords.contains { name.lowercased().contains($0) }
                    return OllamaModelInfo(name: name, size: size, supportsVision: hasVision)
                }

                await MainActor.run {
                    availableModels = parsed.sorted { $0.name < $1.name }
                    isConnected = true
                }
            }
        } catch {
            await MainActor.run { isConnected = false; availableModels = [] }
        }
    }

    // MARK: - Streaming Generation

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
        cancelGeneration()

        let settings = SettingsManager.shared
        let modelName = settings.ollamaModelName
        guard !modelName.isEmpty else {
            Task { @MainActor in
                onComplete(.failure(OllamaError.noModel))
            }
            return
        }

        isGenerating = true
        statusMessage = nil

        // Set deferred screenshot data
        if let deferred = deferredImageData {
            toolExecutor.deferredScreenshotData = deferred
        }

        currentTask = Task {
            // Reset overlay for this generation
            await MainActor.run {
                AgentOverlayManager.shared.resetForNewGeneration()
            }
            
            do {
                var toolExchange: [[String: Any]] = []
                var shouldContinue = true
                var fullText = ""
                var toolIterations = 0
                let maxToolIterations = 100
                // Track if screenshot was injected via tool
                var injectedScreenshotData: Data? = nil

                while shouldContinue {
                    try Task.checkCancellation()

                    let (text, functionCall, screenshotInjected) = try await performStreamingRequest(
                        prompt: prompt,
                        imageData: imageData,
                        injectedScreenshotData: injectedScreenshotData,
                        attachments: attachments,
                        activeContextText: activeContextText,
                        conversationHistory: conversationHistory,
                        toolExchange: toolExchange,
                        onToken: onToken
                    )

                    fullText += text

                    if let call = functionCall {
                        toolIterations += 1

                        if toolIterations > maxToolIterations {
                            fullText += "\n\n*[Stopped: reached the maximum of \(maxToolIterations) tool calls for this turn.]*"
                            shouldContinue = false
                            continue
                        }

                        // Auto-update overlay BEFORE tool execution
                        let (icon, label) = self.toolDisplayInfo(call: call)
                        await MainActor.run {
                            AgentOverlayManager.shared.startTool(name: call.name, step: toolIterations, maxSteps: maxToolIterations)
                            self.statusMessage = "\(icon) \(label) (\(toolIterations)/\(maxToolIterations))"
                        }

                        // Execute tool
                        let (result, screenshotData) = toolExecutor.execute(
                            toolName: call.name,
                            args: call.args
                        )
                        
                        // Auto-update overlay AFTER tool execution
                        await MainActor.run {
                            AgentOverlayManager.shared.endTool(icon: icon, label: label)
                        }

                        // If screenshot was requested/taken and returned, inject it
                        if (call.name == "request_screenshot" || call.name == "take_screenshot"), let ssData = screenshotData {
                            injectedScreenshotData = ssData
                        }

                        // Add tool call and response to exchange
                        toolExchange.append([
                            "role": "assistant",
                            "content": NSNull(),
                            "tool_calls": [[
                                "id": "call_\(toolIterations)",
                                "type": "function",
                                "function": [
                                    "name": call.name,
                                    "arguments": (try? JSONSerialization.data(withJSONObject: call.args ?? [:]))
                                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                                ]
                            ]]
                        ])
                        toolExchange.append([
                            "role": "tool",
                            "tool_call_id": "call_\(toolIterations)",
                            "content": result
                        ])

                        await MainActor.run { self.statusMessage = nil }
                    } else {
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

    /// Cancels any in-progress generation.
    func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
        statusMessage = nil
        AgentOverlayManager.shared.isVisible = false
    }

    // MARK: - Tool Display Helpers
    
    /// Returns a human-readable (icon, label) pair for a tool call.
    private func toolDisplayInfo(call: FunctionCall) -> (String, String) {
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
        toolExchange: [[String: Any]],
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> (fullText: String, functionCall: FunctionCall?, screenshotInjected: Bool) {

        let settings = SettingsManager.shared
        let endpoint = settings.ollamaEndpoint.trimmingCharacters(in: .whitespaces)
        let modelName = settings.ollamaModelName

        guard let url = URL(string: "\(endpoint)/v1/chat/completions") else {
            throw OllamaError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // Build messages array
        var messages: [[String: Any]] = []

        // System message
        messages.append([
            "role": "system",
            "content": settings.systemPrompt
        ])

        // Conversation history
        for message in conversationHistory {
            let role = message.role == .user ? "user" : "assistant"
            messages.append([
                "role": role,
                "content": message.content
            ])
        }

        // Current user message
        var userContent: Any

        // Check if we have images to send
        let hasImages = imageData != nil || injectedScreenshotData != nil || attachments.contains(where: { $0.mimeType.starts(with: "image/") })

        if hasImages {
            // Use multimodal content format
            var contentParts: [[String: Any]] = []

            // Add images
            if let imgData = injectedScreenshotData ?? imageData {
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(imgData.base64EncodedString())"]
                ])
            }

            for attachment in attachments {
                if attachment.mimeType.starts(with: "image/") {
                    contentParts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(attachment.mimeType);base64,\(attachment.data.base64EncodedString())"]
                    ])
                }
            }

            // Build text prompt
            var finalPrompt = prompt
            if let activeContext = activeContextText, !activeContext.isEmpty {
                finalPrompt = "Active window context:\n\(activeContext)\n\nUser question: \(prompt)"
            }

            contentParts.append([
                "type": "text",
                "text": finalPrompt
            ])

            userContent = contentParts
        } else {
            // Plain text
            var finalPrompt = prompt
            if let activeContext = activeContextText, !activeContext.isEmpty {
                finalPrompt = "Active window context:\n\(activeContext)\n\nUser question: \(prompt)"
            }
            userContent = finalPrompt
        }

        messages.append([
            "role": "user",
            "content": userContent
        ])

        // Append tool exchange
        messages.append(contentsOf: toolExchange)

        // Build request body
        var requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "stream": true,
            "temperature": 0.7,
            "max_tokens": 8192
        ]

        // Add tools
        let tools = toolExecutor.openAIToolDeclarations()
        if !tools.isEmpty {
            requestBody["tools"] = tools
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Stream the response
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw OllamaError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        var fullText = ""
        var pendingFunctionCall: FunctionCall? = nil

        for try await line in bytes.lines {
            try Task.checkCancellation()

            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            // Check for [DONE]
            if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

            guard let data = jsonString.data(using: .utf8) else { continue }

            if let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = chunk["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any] {

                // Text content
                if let content = delta["content"] as? String {
                    fullText += content
                    await onToken(content)
                }

                // Tool calls
                if let toolCalls = delta["tool_calls"] as? [[String: Any]],
                   let toolCall = toolCalls.first,
                   let function = toolCall["function"] as? [String: Any],
                   let name = function["name"] as? String {

                    let argsString = function["arguments"] as? String ?? "{}"
                    var args: [String: String]? = nil
                    if let argsData = argsString.data(using: .utf8),
                       let parsedArgs = try? JSONSerialization.jsonObject(with: argsData) as? [String: String] {
                        args = parsedArgs
                    }

                    pendingFunctionCall = FunctionCall(name: name, args: args)
                }
            }
        }

        return (fullText, pendingFunctionCall, false)
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case noModel
    case invalidEndpoint
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noModel:
            return "No Ollama model selected. Configure a model in Settings → Providers & Models."
        case .invalidEndpoint:
            return "Invalid Ollama endpoint URL."
        case .invalidResponse:
            return "Invalid response from Ollama."
        case .apiError(let code, let message):
            return "Ollama Error (\(code)): \(message)"
        }
    }
}

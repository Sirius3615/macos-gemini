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

/// Direct REST API client for Gemini with streaming SSE support.
/// No Firebase dependency — uses raw URLSession against generativelanguage.googleapis.com.
final class GeminiService: ObservableObject {

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    @Published var selectedModel: GeminiModel = .pro31Preview
    @Published var isGenerating: Bool = false

    /// Current streaming task (for cancellation).
    private var currentTask: Task<Void, Never>?

    // MARK: - Streaming Generation

    /// Sends a message with optional image context and streams the response token-by-token.
    func streamGenerate(
        prompt: String,
        imageData: Data?,
        attachments: [ChatAttachment] = [],
        activeContextText: String? = nil,
        conversationHistory: [ChatMessage],
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

        currentTask = Task {
            do {
                let fullText = try await performStreamingRequest(
                    prompt: prompt,
                    imageData: imageData,
                    attachments: attachments,
                    activeContextText: activeContextText,
                    conversationHistory: conversationHistory,
                    apiKey: apiKey,
                    onToken: onToken
                )
                await MainActor.run {
                    self.isGenerating = false
                    onComplete(.success(fullText))
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
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
    }

    // MARK: - Private: HTTP + SSE

    private func performStreamingRequest(
        prompt: String,
        imageData: Data?,
        attachments: [ChatAttachment],
        activeContextText: String?,
        conversationHistory: [ChatMessage],
        apiKey: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {

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

        // Build the request body
        let body = buildRequestBody(
            prompt: prompt,
            imageData: imageData,
            attachments: attachments,
            activeContextText: activeContextText,
            conversationHistory: conversationHistory
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Stream the response
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Try to read error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw GeminiError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse SSE stream
        var fullText = ""

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
                    }
                }
            }
        }

        return fullText
    }

    // MARK: - Request Body Builder

    private func buildRequestBody(
        prompt: String,
        imageData: Data?,
        attachments: [ChatAttachment],
        activeContextText: String?,
        conversationHistory: [ChatMessage]
    ) -> [String: Any] {

        var contents: [[String: Any]] = []

        // Add conversation history (multi-turn)
        for message in conversationHistory {
            let role = message.role == .user ? "user" : "model"
            contents.append([
                "role": role,
                "parts": [["text": message.content]]
            ])
        }

        // Build current user message parts
        var parts: [[String: Any]] = []

        // Add screenshot if available
        if let imageData = imageData {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
        }
        
        // Add other attachments
        for attachment in attachments {
            parts.append([
                "inline_data": [
                    "mime_type": attachment.mimeType,
                    "data": attachment.data.base64EncodedString()
                ]
            ])
        }

        // Final text part with context
        var finalPrompt = prompt
        var contextParts: [String] = []
        
        if imageData != nil {
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
        
        parts.append(["text": finalPrompt])

        contents.append([
            "role": "user",
            "parts": parts
        ])

        var body: [String: Any] = ["contents": contents]

        // Add system instruction
        body["systemInstruction"] = [
            "parts": [["text": SettingsManager.shared.systemPrompt]]
        ]

        // Generation config
        body["generationConfig"] = [
            "temperature": 0.7,
            "topP": 0.95,
            "maxOutputTokens": 8192
        ]

        return body
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
            // Rough estimate based on image size
            let imgSize = imgData.count
            // A typical 1920x1080 JPEG at 70% quality ≈ 200KB
            // Gemini processes at 768x768 tiles, so ~6 tiles for a full HD image
            let estimatedTiles = max(1, imgSize / 50_000) // rough heuristic
            tokens += estimatedTiles * 258
        }
        
        // Attachment tokens
        for attachment in attachments {
            if attachment.mimeType.starts(with: "image/") {
                let estimatedTiles = max(1, attachment.data.count / 50_000)
                tokens += estimatedTiles * 258
            } else {
                // Text-based attachments
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
    let candidates: [Candidate]?
}

private struct Candidate: Codable {
    let content: Content?
}

private struct Content: Codable {
    let parts: [Part]?
}

private struct Part: Codable {
    let text: String?
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

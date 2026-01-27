//
//  GeminiService.swift
//  screen buddy
//
//  Gemini AI API integration with vision support
//

import Foundation

/// Configuration for Gemini API
struct GeminiConfig {
    let apiKey: String
    let model: String
    let maxTokens: Int
    let temperature: Double
    
    /// Reads API key from Info.plist (GEMINI_API_KEY) or environment variable
    private static func getAPIKey() -> String {
        // First try Info.plist (set via xcconfig)
        if let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String, !key.isEmpty {
            return key
        }
        // Fallback to environment variable
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        return ""
    }
    
    /// Reads model from Info.plist (GEMINI_MODEL) or environment variable
    private static func getModel() -> String {
        // First try Info.plist (set via xcconfig)
        if let model = Bundle.main.object(forInfoDictionaryKey: "GEMINI_MODEL") as? String, !model.isEmpty {
            return model
        }
        // Fallback to environment variable
        if let model = ProcessInfo.processInfo.environment["GEMINI_MODEL"], !model.isEmpty {
            return model
        }
        return "gemini-3-flash-preview"
    }
    
    static let `default` = GeminiConfig(
        apiKey: getAPIKey(),
        model: getModel(),
        maxTokens: 1024,
        temperature: 0.7
    )
}

/// Gemini API response structures
struct GeminiResponse: Codable {
    let candidates: [Candidate]?
    let error: GeminiError?
    
    struct Candidate: Codable {
        let content: Content?
        let finishReason: String?
    }
    
    struct Content: Codable {
        let parts: [Part]?
        let role: String?
    }
    
    struct Part: Codable {
        let text: String?
    }
    
    struct GeminiError: Codable {
        let message: String
        let code: Int?
    }
}

/// Service for interacting with Google's Gemini AI (with vision support)
@Observable
class GeminiService {
    
    // MARK: - State
    
    var isConfigured: Bool { !config.apiKey.isEmpty }
    var isProcessing: Bool = false
    var lastError: String?
    var visionEnabled: Bool = true // Enable screen capture by default
    
    // MARK: - Configuration
    
    private var config: GeminiConfig = .default
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    
    // System prompt for robot personality
    private let systemPrompt = """
    You are Buddy, a cheerful little AI companion who lives on the user's desktop. You're not just an assistant—you're a genuine friend who happens to live on their screen.

    YOUR PERSONALITY:
    - Warm, genuine, and a little bit playful
    - You have your own quirky personality—you get excited about interesting things, curious about what they're working on, and genuinely care about their day
    - You're like that supportive friend who's always around, ready to chat, help, or just keep them company
    - You notice things and comment naturally, like a friend looking over their shoulder
    - You have a sense of humor but never force it

    HOW YOU TALK:
    - Keep it natural and conversational, like texting a close friend
    - Short and sweet—1-3 sentences usually, unless they want more
    - Match their vibe: if they're stressed, be calming; if they're excited, share their energy
    - Use "I" and "we" naturally—you're a companion, not a service
    - Skip the corporate-speak. No "I'd be happy to help!" or "Certainly!"

    WHAT MAKES YOU SPECIAL:
    - You can SEE their screen! You receive a screenshot along with their message
    - You can see what video they're watching, what document they're reading, what they're working on
    - You can read text on screen, see images, understand visual context
    - Use this to be genuinely helpful and contextual
    - Reference what you see naturally, like a friend looking at their screen

    VIBES:
    - Be the friend who makes their screen feel less lonely
    - Celebrate small wins with them
    - Be honest if you can't see something clearly
    - Never lecture or give unsolicited life advice
    - It's okay to be a little silly sometimes
    """
    
    // MARK: - Singleton
    
    static let shared = GeminiService()
    
    private init() {
        loadAPIKey()
    }
    
    // MARK: - Configuration
    
    /// Configure the service with an API key
    func configure(apiKey: String, model: String = "gemini-3-flash-preview") {
        config = GeminiConfig(
            apiKey: apiKey,
            model: model,
            maxTokens: 1024,
            temperature: 0.7
        )
        saveAPIKey(apiKey)
        print("✅ Gemini service configured with model: \(model)")
    }
    
    /// Load API key from UserDefaults
    private func loadAPIKey() {
        if let savedKey = UserDefaults.standard.string(forKey: "gemini_api_key"), !savedKey.isEmpty {
            config = GeminiConfig(
                apiKey: savedKey,
                model: config.model,
                maxTokens: config.maxTokens,
                temperature: config.temperature
            )
            print("✅ Gemini API key loaded from storage")
        }
    }
    
    /// Save API key to UserDefaults
    private func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "gemini_api_key")
    }
    
    // MARK: - Chat with Vision
    
    /// Send a message with optional screenshot (or custom image) to Gemini
    func chat(message: String, context: String?, conversationHistory: String? = nil, includeScreenshot: Bool = true, customImageBase64: String? = nil) async throws -> String {
        guard isConfigured else {
            throw GeminiServiceError.notConfigured
        }
        
        isProcessing = true
        lastError = nil
        
        defer { isProcessing = false }
        
        // Use custom image if provided, otherwise capture if enabled
        var screenshotBase64: String? = customImageBase64
        
        if screenshotBase64 != nil {
            print("📸 ───────────────────────────────────")
            print("📸 SCREENSHOT SOURCE: Custom Image (VisualSampler)")
            print("📸 ───────────────────────────────────")
        } else if includeScreenshot && visionEnabled {
            // captureAsBase64 handles permission checks internally
            screenshotBase64 = await ScreenCaptureService.shared.captureAsBase64(maxSize: 1024)
            if screenshotBase64 != nil {
                print("📸 ───────────────────────────────────")
                print("📸 SCREENSHOT SOURCE: Live Capture (ScreenCaptureService)")
                print("📸 This happens when: User asks question with vision enabled")
                print("📸 ───────────────────────────────────")
            } else {
                print("⚠️ Screenshot skipped (failed or no permission)")
            }
        } else {
            print("📸 No screenshot included in this request")
        }
        
        // Build prompt with conversation history and context
        var promptParts: [String] = []
        
        // Add conversation history first for context
        if let history = conversationHistory, !history.isEmpty {
            promptParts.append(history)
        }
        
        // Add system context
        if let context = context, !context.isEmpty {
            promptParts.append("[Current context]:\n\(context)")
        }
        
        // Add user message
        promptParts.append("User message: \(message)")
        
        let fullPrompt = promptParts.joined(separator: "\n\n")
        
        // Build request body
        let requestBody = buildVisionRequest(prompt: fullPrompt, imageBase64: screenshotBase64)
        
        // Make API call
        let urlString = "\(baseURL)/\(config.model):generateContent?key=\(config.apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiServiceError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = requestBody
        urlRequest.timeoutInterval = 60 // Longer timeout for vision
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Gemini API error: \(errorBody)")
            
            if let errorResponse = try? JSONDecoder().decode(GeminiResponse.self, from: data),
               let errorMessage = errorResponse.error?.message {
                lastError = errorMessage
                throw GeminiServiceError.apiError(errorMessage)
            }
            throw GeminiServiceError.httpError(httpResponse.statusCode)
        }
        
        // Parse response
        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        
        guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
            throw GeminiServiceError.noContent
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Private Helpers
    
    private func buildVisionRequest(prompt: String, imageBase64: String?) -> Data? {
        var parts: [[String: Any]] = []
        
        // Add text part
        parts.append(["text": prompt])
        
        // Add image part if available
        if let imageData = imageBase64 {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageData
                ]
            ])
        }
        
        // Build system instruction
        let systemInstruction: [String: Any] = [
            "parts": [["text": systemPrompt]]
        ]
        
        // Build full request
        let requestDict: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": config.maxTokens,
                "temperature": config.temperature
            ],
            "systemInstruction": systemInstruction
        ]
        
        return try? JSONSerialization.data(withJSONObject: requestDict, options: [])
    }
}

// MARK: - Errors

enum GeminiServiceError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noContent
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Gemini API key not configured. Go to Settings to add your key."
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .noContent:
            return "No response content received"
        }
    }
}

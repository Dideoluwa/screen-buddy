//
//  ObserveScreenTool.swift
//  screen buddy
//
//  Vision-based screen observation for agent feedback
//

import Foundation

/// Capture and analyze the current screen state using Gemini Vision
class ObserveScreenTool: BaseAgentTool {
    
    private let geminiService = GeminiService.shared
    
    init() {
        super.init(
            name: "observe_screen",
            description: "Look at the screen and describe what is visible",
            parameterSchema: [
                "focus": "Optional: what to look for (e.g., 'search results', 'error message', 'button')"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let focus = params["focus"] ?? "the current screen state"
        
        print("👁️ ObserveScreenTool: Analyzing screen for '\(focus)'")
        
        // Capture screenshot
        guard let screenshotBase64 = await ScreenCaptureService.shared.captureAsBase64(maxSize: 1024) else {
            return "Could not capture screen. Please make sure screen recording permission is granted."
        }
        
        // Ask Gemini to analyze the screenshot
        let prompt = """
        Describe what you see on this screen, focusing on: \(focus)
        
        Be concise but specific. If you see:
        - Search results: List the first few results
        - Error messages: Quote the error text
        - Forms/Inputs: Describe what's in them
        - Buttons/Links: Name visible interactive elements
        
        Keep response under 200 words.
        """
        
        do {
            let description = try await geminiService.chat(
                message: prompt,
                context: nil,
                conversationHistory: nil,
                includeScreenshot: false,
                customImageBase64: screenshotBase64
            )
            
            print("👁️ Screen observation: \(description.prefix(200))...")
            return description
        } catch {
            return "Failed to analyze screen: \(error.localizedDescription)"
        }
    }
}

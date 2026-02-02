//
//  InteractionManager.swift
//  screen buddy
//
//  Central coordinator for user interactions and AI responses
//

import Foundation
import SwiftUI

/// Manages text input/output and coordinates with AI service
@Observable
class InteractionManager {
    
    // MARK: - State
    
    var isProcessing: Bool = false
    var currentResponse: String = ""
    var responseQueue: [String] = []
    var lastUserInput: String = ""
    var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let contextEngine = ContextEngine.shared
    private let geminiService = GeminiService.shared
    private let chatHistoryManager = ChatHistoryManager.shared
    
    // MARK: - Singleton
    
    static let shared = InteractionManager()
    
    private init() {}
    
    // MARK: - Setup
    
    private weak var panelController: FloatingPanelController?
    
    func setPanelController(_ controller: FloatingPanelController) {
        self.panelController = controller
    }
    
    // MARK: - Input Handling
    
    /// Process user text input
    func handleUserInput(_ text: String, robotState: RobotState) async {
        guard !text.isEmpty else { return }
        
        lastUserInput = text
        isProcessing = true
        errorMessage = nil
        
        print("📝 [USER INPUT]: \(text)")
        
        // Check if Agent Mode is explicitly enabled OR if this should be auto-detected
        if robotState.agentModeEnabled || shouldUseAgentMode(text) {
            if robotState.agentModeEnabled {
                print("🤖 [AGENT MODE ON] Processing with smart agent")
            }
            await handleAgentRequest(text, robotState: robotState)
            return
        }
        
        // Add user message to history
        await MainActor.run {
            let message = ChatMessage(text: text, isUser: true, timestamp: Date())
            robotState.chatHistory.append(message)
            
            // Save history after adding user message
            chatHistoryManager.save(robotState.chatHistory)
            
            // Show bubble immediately to show user message
            robotState.showResponseBubble = true
            
            robotState.expression = .thinking
            robotState.showInputBubble = false
        }
        
        // Get current context
        let contextSnapshot = contextEngine.getContextSnapshot()
        
        // Check if Gemini is configured
        if geminiService.isConfigured {
            await fetchGeminiResponse(text: text, context: contextSnapshot, robotState: robotState)
        } else {
            await showFallbackResponse(text: text, context: contextSnapshot, robotState: robotState)
        }
    }
    
    // MARK: - Agent Mode
    
    /// Detect if the user input should trigger Agent Mode
    private func shouldUseAgentMode(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Action verbs that indicate the user wants something done, not just discussed
        let actionVerbs = [
            "open ", "launch ", "start ",       // App launching
            "create ", "make ", "new ",          // Creating things
            "install ", "download ", "get ",     // Installing
            "run ", "execute ", "build ",        // Running commands
            "search for", "look up", "find ",   // Searching
            "set up", "setup", "configure"       // Setup tasks
        ]
        
        // Check if any action verb is present
        let hasActionVerb = actionVerbs.contains { lowercased.contains($0) }
        
        // Also check for specific patterns that imply action
        let actionPatterns = [
            "and then",      // Multi-step requests
            "after that",
            "folder",        // File system operations
            "directory",
            "terminal",
            "command",
            "project",       // Project setup
            "boilerplate",
            "react app",
            "npm",
            "npx"
        ]
        
        let hasActionPattern = actionPatterns.contains { lowercased.contains($0) }
        
        // Exclude questions that are just asking about how to do something
        let isJustAsking = lowercased.hasPrefix("how do i") || 
                          lowercased.hasPrefix("how can i") ||
                          lowercased.hasPrefix("what is") ||
                          lowercased.hasPrefix("explain")
        
        let shouldUseAgent = (hasActionVerb || hasActionPattern) && !isJustAsking
        
        print("🔍 Agent Mode Detection:")
        print("   Action Verb: \(hasActionVerb)")
        print("   Action Pattern: \(hasActionPattern)")
        print("   Just Asking: \(isJustAsking)")
        print("   → Use Agent: \(shouldUseAgent)")
        
        return shouldUseAgent
    }
    
    /// Handle request using Agent Mode
    private func handleAgentRequest(_ text: String, robotState: RobotState) async {
        print("🤖 [AGENT MODE] Processing: \(text)")
        
        // Add user message to history
        await MainActor.run {
            let message = ChatMessage(text: text, isUser: true, timestamp: Date())
            robotState.chatHistory.append(message)
            chatHistoryManager.save(robotState.chatHistory)
            
            // Set up agent mode UI
            robotState.isAgentMode = true
            robotState.showResponseBubble = true
            robotState.expression = .thinking
            robotState.agentProgress = "Planning..."
        }
        
        // Execute via AgentLoopController
        let controller = AgentLoopController.shared
        
        // Set up observation of agent progress
        let progressTask = Task { @MainActor in
            var lastMessageCount = 0
            while controller.state.isActive {
                // Update UI with progress
                if controller.progressMessages.count > lastMessageCount {
                    robotState.agentProgressMessages = controller.progressMessages
                    if let latest = controller.progressMessages.last {
                        robotState.agentProgress = latest
                    }
                    lastMessageCount = controller.progressMessages.count
                }
                
                // Update step counter
                if case .executing(let step, let total) = controller.state {
                    robotState.currentAgentStep = step
                    robotState.totalAgentSteps = total
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
        }
        
        // Execute the agent
        let result = await controller.execute(userIntent: text)
        
        // Cancel progress observation
        progressTask.cancel()
        
        // Update UI with result
        await MainActor.run {
            isProcessing = false
            robotState.isAgentMode = false
            robotState.agentProgress = ""
            robotState.currentAgentStep = 0
            robotState.totalAgentSteps = 0
            
            // Add result to chat history
            let message = ChatMessage(text: result, isUser: false, timestamp: Date())
            robotState.chatHistory.append(message)
            chatHistoryManager.save(robotState.chatHistory)
            
            robotState.expression = controller.state == .aborted(reason: "") ? .surprised : .happy
            robotState.currentResponse = result
            robotState.showResponseBubble = true
        }
    }
    
    /// Fetch response from Gemini AI
    private func fetchGeminiResponse(text: String, context: String?, robotState: RobotState) async {
        // Build conversation history context (exclude the message we just added)
        let historyForContext = Array(robotState.chatHistory.dropLast())
        let conversationHistory = chatHistoryManager.buildContextString(from: historyForContext)
        
        // Smart Screenshot Decision
        let shouldIncludeScreenshot = decideIfScreenshotNeeded(
            userMessage: text,
            context: context,
            isContextAwarenessEnabled: robotState.isContextAwarenessEnabled
        )
        
        do {
            let response = try await geminiService.chat(
                message: text, 
                context: context, 
                conversationHistory: conversationHistory,
                includeScreenshot: shouldIncludeScreenshot
            )
            
            print("🤖 [GEMINI RESPONSE]: \(response)")
            
            await MainActor.run {
                isProcessing = false
                currentResponse = response
                
                // Add AI message to history
                let message = ChatMessage(text: response, isUser: false, timestamp: Date())
                robotState.chatHistory.append(message)
                
                // Save history after AI response
                chatHistoryManager.save(robotState.chatHistory)
                
                robotState.expression = .happy
                robotState.currentResponse = response
                robotState.showResponseBubble = true
            }
            // Auto-hide removed to let user close manually
            
        } catch {
            await MainActor.run {
                isProcessing = false
                errorMessage = error.localizedDescription
                robotState.expression = .surprised
                
                let errorMsg = "Oops! \(error.localizedDescription)"
                robotState.currentResponse = errorMsg
                
                let message = ChatMessage(text: errorMsg, isUser: false, timestamp: Date())
                robotState.chatHistory.append(message)
                
                // Save history after error
                chatHistoryManager.save(robotState.chatHistory)
                
                robotState.showResponseBubble = true
            }
        }
    }
    
    /// Show fallback response when Gemini is not configured
    private func showFallbackResponse(text: String, context: String?, robotState: RobotState) async {
        try? await Task.sleep(nanoseconds: 500_000_000) // Short delay
        
        let response = "⚙️ I need my AI brain! Add your Gemini API key in Settings (menu bar → Settings)."
        
        await MainActor.run {
            isProcessing = false
            currentResponse = response
            robotState.expression = .curious
            robotState.currentResponse = response
            
            let message = ChatMessage(text: response, isUser: false, timestamp: Date())
            robotState.chatHistory.append(message)
            
            // Save history after fallback response
            chatHistoryManager.save(robotState.chatHistory)
            
            robotState.showResponseBubble = true
        }
    }
    
    // MARK: - Response Queue
    
    /// Add a response to the queue
    func queueResponse(_ response: String) {
        responseQueue.append(response)
    }
    
    /// Get next queued response
    func dequeueResponse() -> String? {
        guard !responseQueue.isEmpty else { return nil }
        return responseQueue.removeFirst()
    }
    
    /// Clear all queued responses
    func clearQueue() {
        responseQueue.removeAll()
    }
    
    // MARK: - System Injection
    
    /// Inject a message from the system (e.g., Nudge Manager)
    @MainActor
    func injectSystemMessage(_ text: String) {
        // Find the robot state from the app delegate via shared instance is tricky
        // Instead, we'll traverse via the key window or rely on a delegate pattern
        // For now, let's access via FloatingPanelController if we can, or better:
        // InteractionManager shouldn't know about RobotState directly if not passed in.
        
        // Wait, handleUserInput takes RobotState. 
        // We need the current RobotState.
        // Let's make InteractionManager Observable and have RobotView observe it?
        // Or store a weak reference to the active RobotState.
        
        guard let panelController = self.panelController else {
            print("⚠️ Cannot inject message: Panel controller not set in InteractionManager")
            return
        }
        
        let robotState = panelController.robotState
        
        isProcessing = false
        currentResponse = text
        
        let message = ChatMessage(text: text, isUser: false, timestamp: Date())
        robotState.chatHistory.append(message)
        
        robotState.expression = .happy
        robotState.currentResponse = text
        robotState.showResponseBubble = true
    }

    
    // MARK: - Error Handling
    
    func setError(_ message: String) {
        errorMessage = message
    }
    
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - History Management
    
    func clearHistory(robotState: RobotState) {
        robotState.chatHistory.removeAll()
        robotState.currentResponse = ""
        chatHistoryManager.clearHistory()
        // Keep the window open (showResponseBubble = true) but empty
    }
    
    func closeChat(robotState: RobotState) {
        robotState.showResponseBubble = false
        robotState.expression = .idle
    }
    
    // MARK: - Smart Screenshot Decision
    
    /// Intelligently decides if a screenshot is needed based on multiple factors
    /// This is NOT just keyword matching - it considers the full context
    private func decideIfScreenshotNeeded(
        userMessage: String,
        context: String?,
        isContextAwarenessEnabled: Bool
    ) -> Bool {
        let message = userMessage.lowercased()
        
        // Factor 1: User Intent Analysis
        // These indicate the user specifically wants visual understanding
        let visualIntentIndicators = [
            "look", "see", "show", "screen", "display", "window",
            "what is this", "what's this", "what am i", "what are you seeing",
            "color", "button", "icon", "image", "picture", "photo",
            "error", "bug", "issue", "wrong", "broken", "not working",
            "how do i", "where is", "can't find", "help me find",
            "this", "that", "here" // Demonstrative pronouns often imply visual reference
        ]
        
        let hasVisualIntent = visualIntentIndicators.contains { message.contains($0) }
        
        // Factor 2: Context Richness
        // If we have good context from other sources, we might not need a screenshot
        let hasRichContext = context != nil && context!.count > 100
        let hasAudioTranscript = context?.contains("[Audio Transcript]") ?? false
        let hasVisualEvents = context?.contains("[Visual Events]") ?? false
        
        // Factor 3: Question Type Analysis
        // Abstract questions don't need screenshots
        let abstractQuestionIndicators = [
            "explain", "what is", "how does", "why", "when was",
            "tell me about", "define", "meaning of", "history of",
            "difference between", "compare", "summarize"
        ]
        
        let isAbstractQuestion = abstractQuestionIndicators.contains { message.contains($0) } &&
                                 !message.contains("screen") &&
                                 !message.contains("this")
        
        // Factor 4: Technical Help Detection
        // If user seems stuck or asking for help with something visual
        let helpIndicators = ["help", "stuck", "don't understand", "confused", "error"]
        let needsVisualHelp = helpIndicators.contains { message.contains($0) }
        
        // Decision Logic:
        var shouldCapture = false
        var reason = ""
        
        // HIGH confidence to capture
        if hasVisualIntent && !isAbstractQuestion {
            shouldCapture = true
            reason = "User intent suggests visual context needed"
        }
        // User needs help and we don't have visual context
        else if needsVisualHelp && !hasVisualEvents {
            shouldCapture = true
            reason = "User needs help, no visual events available"
        }
        // We have audio but user is asking about something specific on screen
        else if hasAudioTranscript && message.contains("screen") {
            shouldCapture = true
            reason = "User asking about screen despite having audio"
        }
        // LOW confidence - rely on existing context
        else if hasRichContext || hasAudioTranscript || hasVisualEvents {
            shouldCapture = false
            reason = "Rich context available from other sources"
        }
        // FALLBACK - no context available, might need visual help
        else if !isContextAwarenessEnabled {
            // If context awareness is off, we have no other signals
            shouldCapture = hasVisualIntent || needsVisualHelp
            reason = "Context Awareness off, using intent-based decision"
        }
        
        // Log the decision
        print("📸 ───────────────────────────────────")
        print("📸 SCREENSHOT DECISION: \(shouldCapture ? "YES" : "NO")")
        print("   Reason: \(reason)")
        print("   Visual Intent: \(hasVisualIntent)")
        print("   Rich Context: \(hasRichContext)")
        print("   Has Audio: \(hasAudioTranscript)")
        print("   Has Visual Events: \(hasVisualEvents)")
        print("   Abstract Question: \(isAbstractQuestion)")
        print("📸 ───────────────────────────────────")
        
        return shouldCapture
    }
}

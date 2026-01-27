//
//  NudgeManager.swift
//  screen buddy
//
//  Manages proactive interactions and "nudges" based on user activity
//

import Foundation

/// Manages proactive assistance and personality expressions
@Observable @MainActor
class NudgeManager {
    
    // MARK: - Configuration
    
    /// Time before suggesting a break or checking in (15 minutes)
    var focusedCheckInterval: TimeInterval = 15 * 60
    
    /// Time before commenting on idleness (5 minutes)
    var idleThreshold: TimeInterval = 5 * 60
    
    // MARK: - State
    
    var isActive: Bool = false
    private var isNudging: Bool = false
    private var lastNudgeTime: Date = Date()
    
    // MARK: - Dependencies
    
    private let contextEngine = ContextEngine.shared
    private let interactionManager = InteractionManager.shared
    private let geminiService = GeminiService.shared
    private var checkTimer: Timer?
    
    // MARK: - Singleton
    
    static let shared = NudgeManager()
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isActive else { return }
        isActive = true
        lastNudgeTime = Date()
        
        // Check for opportunities to nudge every minute
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForNudge()
            }
        }
        
        print("💡 Nudge manager started")
    }
    
    func stop() {
        isActive = false
        checkTimer?.invalidate()
        checkTimer = nil
        print("💡 Nudge manager stopped")
    }
    
    // MARK: - Logic
    
    private func checkForNudge() async {
        guard isActive, !isNudging else { return }
        
        // Don't nudge if user is actively chatting (processing a request)
        if interactionManager.isProcessing {
            return
        }
        
        // Don't nudge too frequently (at least 15 mins between nudges)
        guard Date().timeIntervalSince(lastNudgeTime) > 60 * 15 else { return }
        
        let now = Date()
        let timeSinceActivity = now.timeIntervalSince(contextEngine.lastActivityTimestamp)
        let currentContext = contextEngine.currentContext
        
        // 1. Idle Detection (Inactive for > 5 mins)
        if timeSinceActivity > idleThreshold {
            // Only nudge if we haven't nudged about this session yet
            await triggerIdleNudge(context: currentContext)
            return
        }
        
        // 2. Deep Focus Detection (skipped for now)
        
        // 3. Context-Specific Nudge (Random chance if active)
        if Int.random(in: 1...100) <= 5 { // 5% chance every minute if conditions met
            await triggerContextualNudge(context: currentContext)
        }
    }
    
    // MARK: - Triggers
    
    private func triggerIdleNudge(context: SystemContext) async {
        isNudging = true
        defer { isNudging = false; lastNudgeTime = Date() }
        
        // Get full context including visual events and audio transcript
        let fullContext = contextEngine.getContextSnapshot()
        
        let prompt = """
        The user has been idle for a while. You are their desktop companion.
        
        CONTEXT OF WHAT THEY WERE DOING:
        \(fullContext)
        
        ALSO LOOK AT THE CURRENT SCREENSHOT to see what's on screen now.
        
        Generate a SHORT, friendly message checking if they're still there or taking a break.
        Reference what they were watching/doing if you have that context.
        Keep it 1 short sentence.
        """
        
        do {
            let response = try await geminiService.chat(message: prompt, context: nil, includeScreenshot: true)
            
            // Show bubble
            await MainActor.run {
                interactionManager.injectSystemMessage(response)
            }
        } catch {
            print("⚠️ Failed to generate idle nudge: \(error)")
        }
    }
    
    private func triggerContextualNudge(context: SystemContext) async {
        isNudging = true
        defer { isNudging = false; lastNudgeTime = Date() }
        
        // Only nudge for "productive" or "complex" apps where help might be needed, plus media for "watching with you"
        let interestingCategories: Set<AppCategory> = [.codeEditor, .terminal, .design, .productivity, .browser, .mediaPlayer, .videoStreaming]
        guard interestingCategories.contains(context.activeApp.category) else { return }
        
        // Get full context including visual events and audio transcript
        let fullContext = contextEngine.getContextSnapshot()
        
        var prompt = ""
        
        // Special prompt for media/video - use the rich context!
        if context.activeApp.category == .mediaPlayer || context.activeApp.category == .videoStreaming || context.activeApp.category == .browser {
            prompt = """
            You are a friendly companion watching content with the user.
            
            App: \(context.activeApp.name)
            Window: \(context.windowTitle ?? "Unknown")
            
            CONTEXT FROM WATCHING TOGETHER:
            \(fullContext)
            
            CURRENT SCREENSHOT: See what's on screen right now.
            
            Based on the visual events (scene changes you noticed) and any audio transcript, make a SHORT, fun comment like a friend watching with them.
            
            Examples:
            - If action happened: "Whoa, that chase scene was intense!"
            - If educational: "That's a neat trick they just showed!"
            - If dramatic: "I did NOT see that coming..."
            
            Keep it to 1 SHORT sentence. Be specific to what happened, not generic.
            """
        } else {
            prompt = """
            The user is working in \(context.activeApp.name).
            Window title: \(context.windowTitle ?? "Unknown")
            
            CONTEXT:
            \(fullContext)
            
            CURRENT SCREENSHOT: See what's on screen now.
            
            Generate a SHORT, supportive, or curious comment about what they might be doing.
            Example: "Making progress on that code?" or "That design is coming along!"
            Keep it casual, friendly, and SHORT (1 sentence). Do not be annoying.
            """
        }
        
        do {
            let response = try await geminiService.chat(message: prompt, context: nil, includeScreenshot: true)
            await interactionManager.injectSystemMessage(response)
        } catch {
            print("⚠️ Failed to generate contextual nudge: \(error)")
        }
    }
}

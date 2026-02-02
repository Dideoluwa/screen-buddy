//
//  AgentLoopController.swift
//  screen buddy
//
//  Main agent loop implementing Think → Act → Observe → Think
//

import Foundation

/// Controller that manages the agent execution loop
@Observable
class AgentLoopController {
    
    // MARK: - Singleton
    
    static let shared = AgentLoopController()
    
    // MARK: - Safety Guards
    
    let maxSteps = 50  // High limit for complex browsing tasks
    let maxRetriesPerStep = 3
    
    // MARK: - State
    
    var state: AgentState = .idle
    var currentPlan: AgentPlan?
    var stepResults: [StepResult] = []
    var progressMessages: [String] = []
    var currentStepIndex: Int = 0
    
    // Dynamic loop state
    var actionHistory: [ActionHistoryEntry] = []
    var currentGoal: String = ""
    
    // User interaction support
    var pendingQuestion: String = ""
    private var userResponseContinuation: CheckedContinuation<String, Never>?
    
    // MARK: - Dependencies
    
    private let toolRegistry = ToolRegistry.shared
    private let geminiService = GeminiService.shared
    
    // Track recent observations to detect loops
    private var recentObservations: [String] = []
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Main Execution (Dynamic Loop)
    
    /// Execute an agent task using the dynamic observe→think→act loop
    /// - Parameter intent: The user's natural language request
    /// - Returns: Final message to show to user
    @MainActor
    func execute(userIntent: String) async -> String {
        print("🤖 AgentLoopController: Starting DYNAMIC execution for: \(userIntent)")
        
        // Reset state
        reset()
        currentGoal = userIntent
        state = .planning
        addProgress("Understanding your goal...")
        
        do {
            // Execute the dynamic loop
            let result = try await executeDynamicLoop(goal: userIntent)
            
            state = .completed(success: true, message: result)
            addProgress(result)
            return result
            
        } catch let error as AgentError {
            let message = error.localizedDescription ?? "Unknown error"
            state = .aborted(reason: message)
            addProgress("Failed: \(message)")
            return "I ran into an issue: \(message). Would you like me to try again?"
            
        } catch {
            let message = error.localizedDescription
            state = .aborted(reason: message)
            addProgress("Error: \(message)")
            return "Something went wrong: \(message). Let me know if you'd like to try a different approach."
        }
    }
    
    // MARK: - Dynamic Loop (Observe → Think → Act)
    
    /// The main dynamic loop that observes, thinks, and acts step by step
    private func executeDynamicLoop(goal: String) async throws -> String {
        print("\n🔄 Starting DYNAMIC LOOP for goal: \(goal)")
        actionHistory = []
        
        while actionHistory.count < maxSteps {
            // CHECK FOR CANCELLATION
            if case .aborted = state {
                throw AgentError.userCancelled
            }
            
            let stepNum = actionHistory.count + 1
            
            await MainActor.run {
                state = .observing
                addProgress("Observing screen... (step \(stepNum))")
            }
            
            // 1. OBSERVE - Capture current screen
            print("\n👁️ [\(stepNum)] OBSERVING...")
            let screenshotBase64 = await ScreenCaptureService.shared.captureAsBase64(maxSize: 1024)
            
            await MainActor.run {
                state = .adjusting
                addProgress("Thinking about next action...")
            }
            
            // CHECK FOR CANCELLATION
            if case .aborted = state {
                throw AgentError.userCancelled
            }
            
            // 2. THINK - Ask LLM what to do next
            print("🧠 [\(stepNum)] THINKING...")
            let decision = try await decideNextAction(
                goal: goal,
                screenshotBase64: screenshotBase64,
                history: actionHistory
            )
            
            print("💡 [\(stepNum)] Decision: \(decision.action) - \(decision.reason)")
            
            // Handle "ask_user" specially
            if decision.action == "ask_user" {
                let question = decision.params["question"] ?? "Should I proceed?"
                
                await MainActor.run {
                    state = .waitingForUser(question: question)
                    pendingQuestion = question
                    addProgress("❓ \(question)")
                }
                
                // Wait for user response
                let userResponse = await waitForUserResponse()
                
                await MainActor.run {
                    addProgress("You said: \(userResponse)")
                }
                
                // Record interaction in history
                let historyEntry = ActionHistoryEntry(
                    stepNumber: stepNum,
                    action: "ask_user",
                    params: ["question": question, "response": userResponse],
                    observation: "User responded: \(userResponse)",
                    success: true
                )
                actionHistory.append(historyEntry)
                continue
            }
            
            // 3. Check if DONE
            if decision.isDone {
                let message = decision.doneMessage ?? "Goal completed!"
                print("✅ DONE: \(message)")
                return message
            }
            
            await MainActor.run {
                state = .executing(step: stepNum, total: maxSteps)
                currentStepIndex = stepNum
                addProgress(formatActionDescription(decision))
            }
            
            // 4. ACT - Execute the single action
            print("⚡ [\(stepNum)] ACTING: \(decision.action)")
            let result = await executeSingleAction(decision)
            
            // 5. Record in history
            let historyEntry = ActionHistoryEntry(
                stepNumber: stepNum,
                action: decision.action,
                params: decision.params,
                observation: result.observation,
                success: result.success
            )
            actionHistory.append(historyEntry)
            
            print("📝 [\(stepNum)] Result: \(result.success ? "✓" : "✗") - \(result.observation.prefix(100))")
            
            // Check if stuck (last 3 actions failed or same observation)
            if actionHistory.count >= 3 {
                let last3 = actionHistory.suffix(3)
                if last3.allSatisfy({ !$0.success }) {
                    // Force ask user if stuck
                    let entry = ActionHistoryEntry(
                        stepNumber: stepNum + 1,
                        action: "system_note",
                        params: [:],
                        observation: "SYSTEM ALERT: You have failed 3 times in a row. You MUST use 'ask_user' next to ask for help.",
                        success: false
                    )
                    actionHistory.append(entry)
                }
            }
            
            // Minimal delay to let UI update
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        
        // Max steps reached
        throw AgentError.maxStepsExceeded
    }
    
    /// Ask LLM to decide the next single action based on current screen
    private func decideNextAction(
        goal: String,
        screenshotBase64: String?,
        history: [ActionHistoryEntry]
    ) async throws -> AgentDecision {
        
        let historyText = history.isEmpty ? "No actions taken yet." : history.map { $0.summary }.joined(separator: "\n")
        
        let toolsList = toolRegistry.allTools.map { tool in
            "\(tool.name)(\(tool.parameterSchema.keys.joined(separator: ", ")))"
        }.joined(separator: "\n")
        
        let prompt = """
        GOAL: \(goal)

        HISTORY:
        \(historyText)

        AVAILABLE ACTIONS:
        \(toolsList)
        ask_user(question) - Ask the user for confirmation or help (use this if unsure!)
        done(message) - Call when goal is complete or cannot be achieved

        Look at the screenshot and decide the SINGLE best next action.
        
        RULES:
        - Only return ONE action at a time
        - For browser: type search terms naturally (not URLs)
        - Use observe_screen if you need to read text on screen
        - Click specific coordinates when you see something to click
        - If you are unsure or stuck, use "ask_user" to get help
        - Call "done" when the goal is achieved or impossible

        Respond with ONLY this JSON (no markdown):
        {"action":"tool_name","params":{"key":"value"},"reason":"brief explanation"}
        """
        
        let response = try await geminiService.chat(
            message: prompt,
            context: nil,
            conversationHistory: nil,
            includeScreenshot: false,
            customImageBase64: screenshotBase64
        )
        
        print("🧠 LLM Response: \(response)")
        
        // Parse the decision
        guard let jsonData = extractJSON(from: response) else {
            throw AgentError.planGenerationFailed("Invalid JSON response")
        }
        
        return try JSONDecoder().decode(AgentDecision.self, from: jsonData)
    }
    
    /// Execute a single action and return the result
    private func executeSingleAction(_ decision: AgentDecision) async -> StepResult {
        do {
            let observation = try await toolRegistry.execute(
                action: decision.action,
                params: decision.params
            )
            return .success(stepId: "\(actionHistory.count + 1)", observation: observation)
        } catch {
            return .failure(stepId: "\(actionHistory.count + 1)", error: error.localizedDescription)
        }
    }
    
    /// Format action for display
    private func formatActionDescription(_ decision: AgentDecision) -> String {
        switch decision.action {
        case "browser_type":
            let text = decision.params["text"] ?? ""
            let truncated = text.count > 30 ? String(text.prefix(30)) + "..." : text
            return "Typing: \(truncated)"
        case "browser_click":
            return "Clicking at (\(decision.params["x"] ?? "?"), \(decision.params["y"] ?? "?"))"
        case "browser_scroll":
            return "Scrolling \(decision.params["direction"] ?? "")"
        case "open_app":
            return "Opening \(decision.params["app"] ?? "app")"
        default:
            return "\(decision.action): \(decision.reason)"
        }
    }
    
    /// Cancel the current execution
    @MainActor
    func cancel() {
        state = .aborted(reason: "Cancelled by user")
        addProgress("Cancelled")
    }
    
    // MARK: - Plan Generation
    
    private func generatePlan(intent: String) async throws -> AgentPlan {
        let toolDescriptions = toolRegistry.toolDescriptionsForPrompt()
        
        // Compact system prompt to reduce response length
        let systemPrompt = """
        You are an execution planner. Output ONLY compact JSON, no markdown.

        TOOLS: \(toolDescriptions)

        FORMAT: {"goal":"...","steps":[{"id":"1","action":"tool_name","params":{...}}],"stop_condition":"..."}

        FOR WEB SEARCHES - use this sequence:
        1. open_app with app="Safari" or "Google Chrome"
        2. browser_focus_search to focus address bar
        3. browser_type with text="your search query here" (use natural language with spaces, NOT URLs)
        4. browser_press_enter to search
        5. browser_scroll to view results
        6. observe_screen to see what's displayed
        
        IMPORTANT: Just type the search terms naturally like "best solar generators" - the browser will search automatically.
        DO NOT type URLs. Just type what you want to search for.

        OTHER USAGE:
        - run_shell for terminal commands
        - create_directory for folders
        
        Keep plans at 4-6 steps for searches.
        """
        
        let userMessage = "Plan: \(intent)"
        
        // Try up to 2 times in case of truncation
        for attempt in 1...2 {
            print("🔄 Plan generation attempt \(attempt)/2")
            
            // Call Gemini to generate the plan
            let response = try await geminiService.chat(
                message: userMessage,
                context: systemPrompt,
                conversationHistory: nil,
                includeScreenshot: false
            )
            
            // Log raw LLM response
            logLLMResponse(response)
            
            // Parse the JSON response
            if let jsonData = extractJSON(from: response) {
                do {
                    let plan = try JSONDecoder().decode(AgentPlan.self, from: jsonData)
                    return plan
                } catch {
                    print("❌ JSON parsing error (attempt \(attempt)): \(error)")
                    if attempt == 2 {
                        throw AgentError.planGenerationFailed("Invalid JSON: \(error.localizedDescription)")
                    }
                }
            } else {
                print("❌ Could not extract JSON (attempt \(attempt))")
                if attempt == 2 {
                    throw AgentError.planGenerationFailed("Response was incomplete or not valid JSON")
                }
            }
            
            // Wait before retry
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        throw AgentError.planGenerationFailed("Failed after retries")
    }
    
    // MARK: - Main Loop (Self-Healing)
    
    private func executeLoop(plan: AgentPlan) async throws -> String {
        var steps = plan.steps
        currentStepIndex = 0
        var totalStepsExecuted = 0
        
        while currentStepIndex < steps.count {
            // Safety check: max total steps
            totalStepsExecuted += 1
            if totalStepsExecuted > maxSteps {
                throw AgentError.maxStepsExceeded
            }
            
            var step = steps[currentStepIndex]
            
            // Update state
            await MainActor.run {
                state = .executing(step: currentStepIndex + 1, total: steps.count)
                addProgress(step.displayDescription)
            }
            
            // Log step execution start
            logStepStart(step, index: currentStepIndex + 1, total: steps.count)
            
            // Execute the step
            let result = await executeSingleStep(step)
            stepResults.append(result)
            
            // Log observation
            logObservation(result)
            
            // Check for repeated observations (stuck in loop)
            if isStuck(observation: result.observation) {
                throw AgentError.noProgressDetected
            }
            
            // Handle failure with self-healing
            if !result.success || result.observation.lowercased().contains("failed") || result.observation.lowercased().contains("error") {
                await MainActor.run {
                    state = .adjusting
                    addProgress("🔍 Analyzing what went wrong...")
                }
                
                // Ask LLM to analyze the error and decide what to do
                let recovery = await analyzeErrorAndDecide(step: step, error: result.observation, plan: plan)
                
                switch recovery {
                case .fixAndRetry(let correctedParams, let explanation):
                    await MainActor.run {
                        addProgress("💡 \(explanation)")
                    }
                    
                    // Create corrected step and retry
                    let correctedStep = AgentStep(id: step.id, action: step.action, params: correctedParams)
                    steps[currentStepIndex] = correctedStep
                    
                    logStepStart(correctedStep, index: currentStepIndex + 1, total: steps.count)
                    let retryResult = await executeSingleStep(correctedStep)
                    stepResults.append(retryResult)
                    logObservation(retryResult)
                    
                    if !retryResult.success {
                        throw AgentError.stepExecutionFailed(retryResult.error ?? "Fix failed")
                    }
                    currentStepIndex += 1
                    
                case .askUser(let question):
                    await MainActor.run {
                        state = .waitingForUser(question: question)
                        pendingQuestion = question
                        addProgress("❓ \(question)")
                    }
                    
                    // Wait for user response
                    let userResponse = await waitForUserResponse()
                    
                    await MainActor.run {
                        addProgress("User said: \(userResponse)")
                    }
                    
                    // If user says yes/continue, retry; otherwise skip
                    let affirmative = ["yes", "y", "ok", "sure", "continue", "retry", "try again"]
                    if affirmative.contains(userResponse.lowercased().trimmingCharacters(in: .whitespaces)) {
                        // Retry same step
                        continue
                    } else {
                        // Skip to next step
                        currentStepIndex += 1
                    }
                    
                case .skip(let reason):
                    await MainActor.run {
                        addProgress("⏭️ Skipping: \(reason)")
                    }
                    currentStepIndex += 1
                    
                case .abort(let reason):
                    throw AgentError.stepExecutionFailed(reason)
                }
            } else {
                // Success - move to next step
                currentStepIndex += 1
            }
        }
        
        // All steps completed
        return "Done! \(plan.goal) completed successfully 🎉"
    }
    
    // MARK: - Step Execution
    
    private func executeSingleStep(_ step: AgentStep) async -> StepResult {
        do {
            let observation = try await toolRegistry.execute(action: step.action, params: step.params)
            return .success(stepId: step.id, observation: observation)
        } catch {
            return .failure(stepId: step.id, error: error.localizedDescription, retryCount: 0)
        }
    }
    
    // MARK: - Error Analysis (Self-Healing)
    
    private func analyzeErrorAndDecide(step: AgentStep, error: String, plan: AgentPlan) async -> ErrorRecoveryDecision {
        let prompt = """
        A step failed. Analyze and decide what to do.

        STEP: \(step.action)
        PARAMS: \(step.params)
        ERROR: \(error)
        GOAL: \(plan.goal)

        Respond with ONLY JSON (no markdown):
        {"action":"fix_and_retry","corrected_params":{...},"explanation":"..."}
        OR {"action":"ask_user","question":"..."}
        OR {"action":"skip","reason":"..."}
        OR {"action":"abort","reason":"..."}

        RULES:
        - fix_and_retry: If you can fix params (e.g., lowercase name, different path)
        - ask_user: If you need user input (e.g., alternative name, confirmation)
        - skip: If step is optional and can be skipped
        - abort: If unrecoverable (e.g., missing dependency)
        """
        
        do {
            let response = try await geminiService.chat(
                message: prompt,
                context: nil,
                conversationHistory: nil,
                includeScreenshot: false
            )
            
            print("🔧 Error Recovery LLM Response: \(response)")
            
            if let jsonData = extractJSON(from: response) {
                let decision = try JSONDecoder().decode(ErrorRecoveryDecision.self, from: jsonData)
                return decision
            }
        } catch {
            print("❌ Error analysis failed: \(error)")
        }
        
        // Default: ask user what to do
        return .askUser(question: "Step failed: \(error). Should I try again?")
    }
    
    // MARK: - User Interaction
    
    /// Wait for user to respond to a question
    private func waitForUserResponse() async -> String {
        await withCheckedContinuation { continuation in
            userResponseContinuation = continuation
        }
    }
    
    /// Called by UI when user responds
    @MainActor
    func provideUserResponse(_ response: String) {
        userResponseContinuation?.resume(returning: response)
        userResponseContinuation = nil
        pendingQuestion = ""
    }
    
    // MARK: - Decision Making
    
    private func evaluateResult(_ result: StepResult, remainingSteps: [AgentStep]) -> LoopDecision {
        // Simple evaluation - in a more advanced version, we'd call LLM here
        
        // Check for success indicators in observation
        let observation = result.observation.lowercased()
        
        let successIndicators = ["successfully", "completed", "created", "opened", "installed", "done"]
        let failureIndicators = ["error", "failed", "not found", "permission denied", "cannot"]
        
        let hasSuccess = successIndicators.contains { observation.contains($0) }
        let hasFailure = failureIndicators.contains { observation.contains($0) }
        
        // If this was the last step, stop
        if remainingSteps.isEmpty {
            return .stop(success: hasSuccess && !hasFailure, message: "All steps completed")
        }
        
        // Continue to next step
        return .continueNext
    }
    
    // MARK: - Loop Detection
    
    private func isStuck(observation: String) -> Bool {
        // Keep last 3 observations
        recentObservations.append(observation)
        if recentObservations.count > 3 {
            recentObservations.removeFirst()
        }
        
        // Check if last 3 observations are identical (stuck)
        if recentObservations.count >= 3 {
            let last = recentObservations.suffix(3)
            if Set(last).count == 1 {
                print("⚠️ Detected stuck loop - same observation 3 times")
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Helpers
    
    private func reset() {
        state = .idle
        currentPlan = nil
        stepResults = []
        progressMessages = []
        currentStepIndex = 0
        recentObservations = []
        actionHistory = []
        currentGoal = ""
    }
    
    @MainActor
    private func addProgress(_ message: String) {
        progressMessages.append(message)
        // Keep only last 10 messages
        if progressMessages.count > 10 {
            progressMessages.removeFirst()
        }
        print("📝 Progress: \(message)")
    }
    
    // MARK: - Detailed Logging
    
    private func logLLMResponse(_ response: String) {
        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║  🧠 LLM RESPONSE                                              ║")
        print("╚══════════════════════════════════════════════════════════════╝")
        print(response)
        print("════════════════════════════════════════════════════════════════")
        print("")
    }
    
    private func logPlan(_ plan: AgentPlan) {
        print("")
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║  📋 AGENT PLAN                                                ║")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║  Goal: \(plan.goal.prefix(50))")
        print("║  Steps: \(plan.steps.count)")
        print("║  Stop Condition: \(plan.stopCondition.prefix(40))")
        print("╠══════════════════════════════════════════════════════════════╣")
        
        for (index, step) in plan.steps.enumerated() {
            print("║  [\(index + 1)] \(step.action)")
            for (key, value) in step.params {
                print("║      └─ \(key): \(value.prefix(40))")
            }
        }
        
        print("╚══════════════════════════════════════════════════════════════╝")
        print("")
    }
    
    private func logStepStart(_ step: AgentStep, index: Int, total: Int) {
        print("")
        print("┌──────────────────────────────────────────────")
        print("│  ⚡ EXECUTING STEP \(index)/\(total)")
        print("├──────────────────────────────────────────────")
        print("│  ID: \(step.id)")
        print("│  Action: \(step.action)")
        print("│  Params:")
        for (key, value) in step.params {
            print("│    \(key): \(value)")
        }
        print("└──────────────────────────────────────────────")
    }
    
    private func logObservation(_ result: StepResult) {
        let statusIcon = result.success ? "✅" : "❌"
        print("")
        print("┌──────────────────────────────────────────────")
        print("│  👁️ OBSERVATION \(statusIcon)")
        print("├──────────────────────────────────────────────")
        print("│  Step ID: \(result.stepId)")
        print("│  Success: \(result.success)")
        if let error = result.error {
            print("│  Error: \(error)")
        }
        print("│  Result:")
        // Split observation into lines for readable output
        let lines = result.observation.components(separatedBy: "\n").prefix(10)
        for line in lines {
            print("│    \(line.prefix(60))")
        }
        if result.observation.components(separatedBy: "\n").count > 10 {
            print("│    ... (truncated)")
        }
        print("└──────────────────────────────────────────────")
        print("")
    }
    
    /// Extract JSON from LLM response (handles markdown code blocks)
    private func extractJSON(from text: String) -> Data? {
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.contains("```json") {
            if let start = jsonString.range(of: "```json"),
               let end = jsonString.range(of: "```", range: start.upperBound..<jsonString.endIndex) {
                jsonString = String(jsonString[start.upperBound..<end.lowerBound])
            }
        } else if jsonString.contains("```") {
            if let start = jsonString.range(of: "```"),
               let end = jsonString.range(of: "```", range: start.upperBound..<jsonString.endIndex) {
                jsonString = String(jsonString[start.upperBound..<end.lowerBound])
            }
        }
        
        // Find JSON object bounds
        guard let firstBrace = jsonString.firstIndex(of: "{"),
              let lastBrace = jsonString.lastIndex(of: "}") else {
            return nil
        }
        
        jsonString = String(jsonString[firstBrace...lastBrace])
        return jsonString.data(using: .utf8)
    }
}

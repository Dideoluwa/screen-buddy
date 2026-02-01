//
//  AgentModels.swift
//  screen buddy
//
//  Data models for the Agent Mode system
//

import Foundation

// MARK: - Agent Plan

/// LLM-generated execution plan containing goal, steps, and stop condition
struct AgentPlan: Codable {
    let goal: String
    let steps: [AgentStep]
    let stopCondition: String
    
    enum CodingKeys: String, CodingKey {
        case goal
        case steps
        case stopCondition = "stop_condition"
    }
}

// MARK: - Agent Step

/// Individual executable step within an agent plan
struct AgentStep: Codable, Identifiable {
    let id: String
    let action: String  // Tool name: "open_app", "run_shell", "create_directory", etc.
    let params: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case id, action, params
    }
    
    init(id: String, action: String, params: [String: String]) {
        self.id = id
        self.action = action
        self.params = params
    }
    
    /// Custom decoder to handle mixed types in params (LLM may return bool, int, or string)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        action = try container.decode(String.self, forKey: .action)
        
        // Decode params as [String: AnyCodable] then convert all values to String
        let rawParams = try container.decode([String: AnyCodableValue].self, forKey: .params)
        var stringParams: [String: String] = [:]
        for (key, value) in rawParams {
            stringParams[key] = value.stringValue
        }
        params = stringParams
    }
    
    /// Human-readable description of what this step does
    var displayDescription: String {
        switch action {
        case "open_app":
            return "Opening \(params["app"] ?? "application")..."
        case "create_directory":
            return "Creating folder \(params["path"] ?? "")..."
        case "create_file":
            return "Creating file \(params["name"] ?? "")..."
        case "run_shell":
            let cmd = params["command"] ?? ""
            let truncated = cmd.count > 50 ? String(cmd.prefix(50)) + "..." : cmd
            return "Running: \(truncated)"
        case "observe_filesystem":
            return "Checking \(params["path"] ?? "")..."
        case "observe_screen":
            return "Looking at screen..."
        case "browser_type":
            let text = params["text"] ?? ""
            let truncated = text.count > 30 ? String(text.prefix(30)) + "..." : text
            return "Typing: \(truncated)"
        case "browser_focus_search":
            return "Focusing address bar..."
        case "browser_press_enter":
            return "Pressing Enter..."
        case "browser_scroll":
            return "Scrolling \(params["direction"] ?? "")..."
        default:
            return "Executing \(action)..."
        }
    }
}

/// Helper to decode any JSON value and convert to string
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            self = .string("")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    
    var stringValue: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return ""
        }
    }
}

// MARK: - Dynamic Agent Decision

/// LLM decision for a single action in the dynamic loop
struct AgentDecision: Codable {
    let action: String        // Tool name or "done"
    let params: [String: String]
    let reason: String        // Why this action was chosen
    
    var isDone: Bool {
        action == "done"
    }
    
    var doneMessage: String? {
        if isDone {
            return params["message"] ?? reason
        }
        return nil
    }
    
    enum CodingKeys: String, CodingKey {
        case action, params, reason
    }
    
    init(action: String, params: [String: String], reason: String) {
        self.action = action
        self.params = params
        self.reason = reason
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        
        // Handle mixed param types
        if let rawParams = try? container.decode([String: AnyCodableValue].self, forKey: .params) {
            var stringParams: [String: String] = [:]
            for (key, value) in rawParams {
                stringParams[key] = value.stringValue
            }
            params = stringParams
        } else {
            params = [:]
        }
    }
}

// MARK: - Action History Entry

/// Record of one action taken in the dynamic loop
struct ActionHistoryEntry {
    let stepNumber: Int
    let action: String
    let params: [String: String]
    let observation: String
    let success: Bool
    let timestamp: Date
    
    init(stepNumber: Int, action: String, params: [String: String], observation: String, success: Bool) {
        self.stepNumber = stepNumber
        self.action = action
        self.params = params
        self.observation = observation
        self.success = success
        self.timestamp = Date()
    }
    
    /// Format for LLM context
    var summary: String {
        let status = success ? "✓" : "✗"
        let paramsStr = params.isEmpty ? "" : " (\(params.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))"
        return "\(stepNumber). \(action)\(paramsStr) \(status)"
    }
}

// MARK: - Step Result

/// Result of executing a single agent step
struct StepResult {
    let stepId: String
    let success: Bool
    let observation: String
    let error: String?
    let retryCount: Int
    
    init(stepId: String, success: Bool, observation: String, error: String? = nil, retryCount: Int = 0) {
        self.stepId = stepId
        self.success = success
        self.observation = observation
        self.error = error
        self.retryCount = retryCount
    }
    
    /// Create a successful result
    static func success(stepId: String, observation: String) -> StepResult {
        StepResult(stepId: stepId, success: true, observation: observation)
    }
    
    /// Create a failed result
    static func failure(stepId: String, error: String, retryCount: Int = 0) -> StepResult {
        StepResult(stepId: stepId, success: false, observation: "", error: error, retryCount: retryCount)
    }
}

// MARK: - Agent State

/// Current state of the agent execution loop
enum AgentState: Equatable {
    case idle
    case planning
    case executing(step: Int, total: Int)
    case observing
    case adjusting  // LLM is adjusting the plan based on observations
    case waitingForUser(question: String)  // Paused, waiting for user input
    case completed(success: Bool, message: String)
    case aborted(reason: String)
    
    var isActive: Bool {
        switch self {
        case .idle, .completed, .aborted:
            return false
        default:
            return true
        }
    }
    
    var isWaitingForUser: Bool {
        if case .waitingForUser = self { return true }
        return false
    }
    
    var displayMessage: String {
        switch self {
        case .idle:
            return ""
        case .planning:
            return "Planning..."
        case .executing(let step, let total):
            return "Step \(step)/\(total)"
        case .observing:
            return "Observing result..."
        case .adjusting:
            return "Analyzing & adjusting..."
        case .waitingForUser(let question):
            return "❓ \(question)"
        case .completed(let success, let message):
            return success ? "✅ \(message)" : "⚠️ \(message)"
        case .aborted(let reason):
            return "❌ \(reason)"
        }
    }
}

// MARK: - Error Recovery Decision

/// LLM decision after analyzing a step failure
enum ErrorRecoveryDecision: Codable {
    case fixAndRetry(correctedParams: [String: String], explanation: String)
    case askUser(question: String)
    case skip(reason: String)
    case abort(reason: String)
    
    enum CodingKeys: String, CodingKey {
        case action
        case correctedParams = "corrected_params"
        case explanation
        case question
        case reason
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)
        
        switch action {
        case "fix_and_retry":
            let params = try container.decodeIfPresent([String: String].self, forKey: .correctedParams) ?? [:]
            let explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? "Fixing and retrying"
            self = .fixAndRetry(correctedParams: params, explanation: explanation)
        case "ask_user":
            let question = try container.decode(String.self, forKey: .question)
            self = .askUser(question: question)
        case "skip":
            let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Skipping step"
            self = .skip(reason: reason)
        case "abort":
            let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Cannot proceed"
            self = .abort(reason: reason)
        default:
            self = .abort(reason: "Unknown error recovery action")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .fixAndRetry(let params, let explanation):
            try container.encode("fix_and_retry", forKey: .action)
            try container.encode(params, forKey: .correctedParams)
            try container.encode(explanation, forKey: .explanation)
        case .askUser(let question):
            try container.encode("ask_user", forKey: .action)
            try container.encode(question, forKey: .question)
        case .skip(let reason):
            try container.encode("skip", forKey: .action)
            try container.encode(reason, forKey: .reason)
        case .abort(let reason):
            try container.encode("abort", forKey: .action)
            try container.encode(reason, forKey: .reason)
        }
    }
}

// MARK: - Loop Decision

/// Decision made by LLM after observing step result
enum LoopDecision: Codable {
    case continueNext           // Proceed to next step
    case retryStep(reason: String)  // Retry current step
    case adjustPlan(newSteps: [AgentStep])  // Modify remaining steps
    case stop(success: Bool, message: String)  // End the loop
    
    enum CodingKeys: String, CodingKey {
        case type
        case reason
        case newSteps = "new_steps"
        case success
        case message
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "continue":
            self = .continueNext
        case "retry":
            let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Retrying step"
            self = .retryStep(reason: reason)
        case "adjust":
            let newSteps = try container.decode([AgentStep].self, forKey: .newSteps)
            self = .adjustPlan(newSteps: newSteps)
        case "stop":
            let success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
            let message = try container.decodeIfPresent(String.self, forKey: .message) ?? "Task completed"
            self = .stop(success: success, message: message)
        default:
            self = .continueNext
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .continueNext:
            try container.encode("continue", forKey: .type)
        case .retryStep(let reason):
            try container.encode("retry", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .adjustPlan(let newSteps):
            try container.encode("adjust", forKey: .type)
            try container.encode(newSteps, forKey: .newSteps)
        case .stop(let success, let message):
            try container.encode("stop", forKey: .type)
            try container.encode(success, forKey: .success)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Agent Error

/// Errors that can occur during agent execution
enum AgentError: LocalizedError {
    case planGenerationFailed(String)
    case stepExecutionFailed(String)
    case toolNotFound(String)
    case maxStepsExceeded
    case maxRetriesExceeded(stepId: String)
    case noProgressDetected
    case userCancelled
    
    var errorDescription: String? {
        switch self {
        case .planGenerationFailed(let reason):
            return "Failed to generate plan: \(reason)"
        case .stepExecutionFailed(let reason):
            return "Step execution failed: \(reason)"
        case .toolNotFound(let toolName):
            return "Tool not found: \(toolName)"
        case .maxStepsExceeded:
            return "Maximum steps exceeded - task may be too complex"
        case .maxRetriesExceeded(let stepId):
            return "Maximum retries exceeded for step \(stepId)"
        case .noProgressDetected:
            return "No progress detected - stuck in loop"
        case .userCancelled:
            return "Cancelled by user"
        }
    }
}

//
//  AgentTool.swift
//  screen buddy
//
//  Protocol defining the interface for all agent tools
//

import Foundation

// MARK: - Agent Tool Protocol

/// Protocol that all agent tools must conform to
protocol AgentTool {
    /// Unique identifier for this tool (e.g., "open_app", "run_shell")
    var name: String { get }
    
    /// Human-readable description of what this tool does
    var description: String { get }
    
    /// Parameters this tool accepts (for LLM context)
    var parameterSchema: [String: String] { get }
    
    /// Execute the tool with given parameters
    /// - Parameter params: Dictionary of parameter name to value
    /// - Returns: Observation string describing the result
    /// - Throws: AgentError if execution fails
    func execute(params: [String: String]) async throws -> String
}

// MARK: - Tool Metadata

/// Metadata about a tool for LLM context generation
struct ToolMetadata: Codable {
    let name: String
    let description: String
    let parameters: [String: String]
    
    init(from tool: AgentTool) {
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameterSchema
    }
}

// MARK: - Base Tool Implementation

/// Base class providing common tool functionality
class BaseAgentTool: AgentTool {
    let name: String
    let description: String
    let parameterSchema: [String: String]
    
    init(name: String, description: String, parameterSchema: [String: String]) {
        self.name = name
        self.description = description
        self.parameterSchema = parameterSchema
    }
    
    func execute(params: [String: String]) async throws -> String {
        fatalError("Subclasses must implement execute(params:)")
    }
    
    /// Helper to get a required parameter or throw
    func requireParam(_ key: String, from params: [String: String]) throws -> String {
        guard let value = params[key], !value.isEmpty else {
            throw AgentError.stepExecutionFailed("Missing required parameter: \(key)")
        }
        return value
    }
    
    /// Helper to expand tilde in paths
    func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + String(path.dropFirst())
        }
        return path
    }
}

//
//  ToolRegistry.swift
//  screen buddy
//
//  Central dispatcher for agent tools
//

import Foundation

/// Central registry that manages and dispatches agent tools
class ToolRegistry {
    
    // MARK: - Singleton
    
    static let shared = ToolRegistry()
    
    // MARK: - Properties
    
    private var tools: [String: AgentTool] = [:]
    
    // MARK: - Initialization
    
    private init() {
        registerDefaultTools()
    }
    
    /// Registers all built-in tools
    private func registerDefaultTools() {
        // Filesystem tools
        register(OpenAppTool())
        register(CreateDirectoryTool())
        register(CreateFileTool())
        register(RunShellTool())
        register(ObserveFilesystemTool())
        
        // Browser automation tools
        register(BrowserNavigateTool())
        register(BrowserTypeTool())
        register(BrowserClickTool())
        register(BrowserScrollTool())
        register(BrowserFocusSearchTool())
        register(BrowserPressEnterTool())
        
        // Vision tools
        register(ObserveScreenTool())
        
        print("🛠️ ToolRegistry: Registered \(tools.count) tools")
    }
    
    // MARK: - Registration
    
    /// Register a new tool
    func register(_ tool: AgentTool) {
        tools[tool.name] = tool
        print("🛠️ Registered tool: \(tool.name)")
    }
    
    /// Unregister a tool by name
    func unregister(_ name: String) {
        tools.removeValue(forKey: name)
    }
    
    /// Get all registered tools
    var allTools: [AgentTool] {
        Array(tools.values)
    }
    
    // MARK: - Execution
    
    /// Execute an action using the appropriate tool
    /// - Parameters:
    ///   - action: The tool name (e.g., "open_app")
    ///   - params: Parameters to pass to the tool
    /// - Returns: Observation string from tool execution
    func execute(action: String, params: [String: String]) async throws -> String {
        guard let tool = tools[action] else {
            throw AgentError.toolNotFound(action)
        }
        
        print("🔧 Executing tool: \(action) with params: \(params)")
        
        let result = try await tool.execute(params: params)
        
        print("✅ Tool \(action) completed: \(result.prefix(100))...")
        
        return result
    }
    
    // MARK: - Tool Information
    
    /// Get metadata for all available tools (for LLM context)
    func availableTools() -> [ToolMetadata] {
        tools.values.map { ToolMetadata(from: $0) }
    }
    
    /// Get tool descriptions as a compact string for LLM prompt
    func toolDescriptionsForPrompt() -> String {
        // Keep it very compact to avoid long prompts
        var descriptions: [String] = []
        
        for tool in tools.values.sorted(by: { $0.name < $1.name }) {
            let params = tool.parameterSchema.map { "\($0.key)" }.joined(separator: ", ")
            descriptions.append("\(tool.name)(\(params))")
        }
        
        return descriptions.joined(separator: " | ")
    }
    
    /// Check if a tool exists
    func hasTool(_ name: String) -> Bool {
        tools[name] != nil
    }
    
    /// Get a specific tool
    func tool(named: String) -> AgentTool? {
        tools[named]
    }
}

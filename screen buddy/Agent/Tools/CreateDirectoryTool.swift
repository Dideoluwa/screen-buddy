//
//  CreateDirectoryTool.swift
//  screen buddy
//
//  Tool for creating directories/folders
//

import Foundation

/// Tool that creates directories on the filesystem
class CreateDirectoryTool: BaseAgentTool {
    
    init() {
        super.init(
            name: "create_directory",
            description: "Creates a new directory/folder at the specified path",
            parameterSchema: [
                "path": "Full path where the directory should be created (e.g., '~/Desktop/myProject')"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let rawPath = try requireParam("path", from: params)
        let path = expandPath(rawPath)
        
        print("📁 CreateDirectoryTool: Creating directory at \(path)...")
        
        let fileManager = FileManager.default
        
        // Check if already exists
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return "Directory already exists at \(rawPath)"
            } else {
                throw AgentError.stepExecutionFailed("A file (not directory) already exists at \(rawPath)")
            }
        }
        
        // Create with intermediate directories
        do {
            try fileManager.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: nil
            )
            
            // Verify creation
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return "Successfully created directory at \(rawPath)"
            } else {
                throw AgentError.stepExecutionFailed("Directory creation returned success but directory not found")
            }
        } catch {
            throw AgentError.stepExecutionFailed("Failed to create directory: \(error.localizedDescription)")
        }
    }
}

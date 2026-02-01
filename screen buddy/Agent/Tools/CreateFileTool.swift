//
//  CreateFileTool.swift
//  screen buddy
//
//  Tool for creating files with optional content
//

import Foundation

/// Tool that creates files on the filesystem
class CreateFileTool: BaseAgentTool {
    
    init() {
        super.init(
            name: "create_file",
            description: "Creates a new file at the specified path with optional content",
            parameterSchema: [
                "path": "Directory path where the file should be created",
                "name": "Name of the file to create (e.g., 'README.md')",
                "content": "(Optional) Content to write to the file"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let rawDir = try requireParam("path", from: params)
        let fileName = try requireParam("name", from: params)
        let content = params["content"] ?? ""
        
        let dirPath = expandPath(rawDir)
        let fullPath = (dirPath as NSString).appendingPathComponent(fileName)
        
        print("📄 CreateFileTool: Creating file at \(fullPath)...")
        
        let fileManager = FileManager.default
        
        // Check if file already exists
        if fileManager.fileExists(atPath: fullPath) {
            return "File already exists at \(rawDir)/\(fileName)"
        }
        
        // Ensure parent directory exists
        let parentDir = (fullPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: parentDir) {
            try fileManager.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        // Create the file
        let data = content.data(using: .utf8)
        let success = fileManager.createFile(atPath: fullPath, contents: data, attributes: nil)
        
        if success {
            let contentInfo = content.isEmpty ? "empty file" : "with \(content.count) characters"
            return "Successfully created \(fileName) at \(rawDir) (\(contentInfo))"
        } else {
            throw AgentError.stepExecutionFailed("Failed to create file at \(fullPath)")
        }
    }
}

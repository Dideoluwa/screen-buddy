//
//  RunShellTool.swift
//  screen buddy
//
//  Tool for executing shell commands
//

import Foundation

/// Tool that executes shell commands and returns output
class RunShellTool: BaseAgentTool {
    
    /// Maximum output length to return (prevents memory issues with large outputs)
    private let maxOutputLength = 2000
    
    /// Maximum execution time in seconds
    private let timeoutSeconds: TimeInterval = 300 // 5 minutes for long-running commands like npm install
    
    init() {
        super.init(
            name: "run_shell",
            description: "Executes a shell command and returns the output. Use for installing packages, running scripts, etc.",
            parameterSchema: [
                "command": "The shell command to execute (e.g., 'npm install', 'npx create-react-app .')",
                "directory": "(Optional) Working directory for the command"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let command = try requireParam("command", from: params)
        let directory = params["directory"].map { expandPath($0) }
        
        print("🖥️ RunShellTool: Executing '\(command)'...")
        if let dir = directory {
            print("   Working directory: \(dir)")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.runCommand(command, in: directory)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func runCommand(_ command: String, in directory: String?) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Set working directory if specified
        if let dir = directory {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }
        
        // Set up environment with PATH including common locations
        var env = ProcessInfo.processInfo.environment
        let additionalPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.nvm/versions/node/*/bin",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin"
        ]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = additionalPaths.joined(separator: ":") + ":" + currentPath
        process.environment = env
        
        // Start the process
        try process.run()
        
        // Wait with timeout
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        if process.isRunning {
            process.terminate()
            throw AgentError.stepExecutionFailed("Command timed out after \(Int(timeoutSeconds)) seconds")
        }
        
        // Collect output
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        // Build result
        var result = ""
        
        if process.terminationStatus == 0 {
            result = "Command completed successfully.\n"
            if !output.isEmpty {
                let truncatedOutput = truncate(output)
                result += "Output:\n\(truncatedOutput)"
            }
        } else {
            result = "Command failed with exit code \(process.terminationStatus).\n"
            if !errorOutput.isEmpty {
                let truncatedError = truncate(errorOutput)
                result += "Error:\n\(truncatedError)"
            }
            if !output.isEmpty {
                let truncatedOutput = truncate(output)
                result += "\nOutput:\n\(truncatedOutput)"
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func truncate(_ text: String) -> String {
        if text.count <= maxOutputLength {
            return text
        }
        
        let halfLength = maxOutputLength / 2
        let start = text.prefix(halfLength)
        let end = text.suffix(halfLength)
        return "\(start)\n\n... [truncated \(text.count - maxOutputLength) characters] ...\n\n\(end)"
    }
}

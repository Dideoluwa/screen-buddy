//
//  ObserveFilesystemTool.swift
//  screen buddy
//
//  Tool for observing filesystem state
//

import Foundation

/// Tool that observes/inspects the filesystem
class ObserveFilesystemTool: BaseAgentTool {
    
    init() {
        super.init(
            name: "observe_filesystem",
            description: "Checks if a file or directory exists and returns information about it",
            parameterSchema: [
                "path": "Path to check (e.g., '~/Desktop/myProject')"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let rawPath = try requireParam("path", from: params)
        let path = expandPath(rawPath)
        
        print("👁️ ObserveFilesystemTool: Checking \(path)...")
        
        let fileManager = FileManager.default
        
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        
        if !exists {
            return "Path does not exist: \(rawPath)"
        }
        
        if isDirectory.boolValue {
            // It's a directory - list contents
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: path)
                
                if contents.isEmpty {
                    return "Directory exists at \(rawPath) but is empty"
                }
                
                // Categorize contents
                var dirs: [String] = []
                var files: [String] = []
                
                for item in contents.prefix(50) { // Limit to 50 items
                    let itemPath = (path as NSString).appendingPathComponent(item)
                    var itemIsDir: ObjCBool = false
                    fileManager.fileExists(atPath: itemPath, isDirectory: &itemIsDir)
                    
                    if itemIsDir.boolValue {
                        dirs.append(item + "/")
                    } else {
                        files.append(item)
                    }
                }
                
                var result = "Directory exists at \(rawPath) with \(contents.count) items:\n"
                
                if !dirs.isEmpty {
                    result += "\nDirectories: \(dirs.joined(separator: ", "))"
                }
                if !files.isEmpty {
                    let fileList = files.prefix(20).joined(separator: ", ")
                    result += "\nFiles: \(fileList)"
                    if files.count > 20 {
                        result += " ... and \(files.count - 20) more"
                    }
                }
                
                // Check for specific project indicators
                let indicators = checkProjectIndicators(contents: contents)
                if !indicators.isEmpty {
                    result += "\n\nProject indicators found: \(indicators.joined(separator: ", "))"
                }
                
                return result
                
            } catch {
                return "Directory exists at \(rawPath) but couldn't list contents: \(error.localizedDescription)"
            }
        } else {
            // It's a file - get info
            do {
                let attrs = try fileManager.attributesOfItem(atPath: path)
                let size = (attrs[.size] as? Int64) ?? 0
                let modDate = attrs[.modificationDate] as? Date
                
                var result = "File exists at \(rawPath)\n"
                result += "Size: \(formatBytes(size))\n"
                if let date = modDate {
                    result += "Modified: \(formatDate(date))"
                }
                
                // If it's a small text file, peek at content
                if size < 1000, let content = fileManager.contents(atPath: path),
                   let text = String(data: content, encoding: .utf8) {
                    result += "\n\nContent preview:\n\(text.prefix(500))"
                }
                
                return result
            } catch {
                return "File exists at \(rawPath) but couldn't read attributes"
            }
        }
    }
    
    /// Check for common project structure indicators
    private func checkProjectIndicators(contents: [String]) -> [String] {
        var indicators: [String] = []
        
        let projectFiles: [(String, String)] = [
            ("package.json", "Node.js project"),
            ("node_modules", "npm packages installed"),
            ("Cargo.toml", "Rust project"),
            ("go.mod", "Go module"),
            ("requirements.txt", "Python project"),
            ("Gemfile", "Ruby project"),
            ("pubspec.yaml", "Dart/Flutter project"),
            ("Package.swift", "Swift package"),
            (".git", "Git repository"),
            ("README.md", "README present"),
            ("src", "src directory present"),
            ("public", "public directory present")
        ]
        
        for (file, description) in projectFiles {
            if contents.contains(file) {
                indicators.append(description)
            }
        }
        
        return indicators
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

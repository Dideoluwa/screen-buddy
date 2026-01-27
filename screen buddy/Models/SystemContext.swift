//
//  SystemContext.swift
//  screen buddy
//
//  Data structures for system context information
//

import Foundation
import AppKit

/// Information about the active application
struct AppInfo: Equatable {
    let name: String
    let bundleIdentifier: String?
    let category: AppCategory
    let isActive: Bool
    
    static let unknown = AppInfo(name: "Unknown", bundleIdentifier: nil, category: .other, isActive: false)
}

/// Categories of applications for context-aware behavior
enum AppCategory: String, CaseIterable {
    case browser = "Browser"
    case codeEditor = "Code Editor"
    case pdfReader = "PDF Reader"
    case mediaPlayer = "Media Player"
    case videoStreaming = "Video Streaming"
    case terminal = "Terminal"
    case notes = "Notes"
    case communication = "Communication"
    case productivity = "Productivity"
    case design = "Design"
    case other = "Other"
    
    /// Determine category from bundle identifier
    static func from(bundleId: String?) -> AppCategory {
        guard let bundleId = bundleId?.lowercased() else { return .other }
        
        // Browsers
        if bundleId.contains("safari") || bundleId.contains("chrome") || 
           bundleId.contains("firefox") || bundleId.contains("brave") ||
           bundleId.contains("edge") || bundleId.contains("arc") {
            return .browser
        }
        
        // Code Editors
        if bundleId.contains("xcode") || bundleId.contains("vscode") || 
           bundleId.contains("cursor") || bundleId.contains("sublime") ||
           bundleId.contains("textmate") || bundleId.contains("atom") ||
           bundleId.contains("jetbrains") || bundleId.contains("idea") ||
           bundleId.contains("android-studio") {
            return .codeEditor
        }
        
        // PDF Readers
        if bundleId.contains("preview") || bundleId.contains("pdf") ||
           bundleId.contains("acrobat") || bundleId.contains("skim") {
            return .pdfReader
        }
        
        // Media Players
        if bundleId.contains("vlc") || bundleId.contains("iina") ||
           bundleId.contains("quicktime") || bundleId.contains("music") ||
           bundleId.contains("spotify") {
            return .mediaPlayer
        }
        
        // Video Streaming
        if bundleId.contains("netflix") || bundleId.contains("youtube") ||
           bundleId.contains("primevideo") || bundleId.contains("disney") ||
           bundleId.contains("hulu") || bundleId.contains("hbomax") {
            return .videoStreaming
        }
        
        // Terminal
        if bundleId.contains("terminal") || bundleId.contains("iterm") ||
           bundleId.contains("warp") || bundleId.contains("alacritty") ||
           bundleId.contains("kitty") {
            return .terminal
        }
        
        // Notes/Writing
        if bundleId.contains("notes") || bundleId.contains("notion") ||
           bundleId.contains("obsidian") || bundleId.contains("bear") ||
           bundleId.contains("evernote") || bundleId.contains("ulysses") {
            return .notes
        }
        
        // Communication
        if bundleId.contains("slack") || bundleId.contains("discord") ||
           bundleId.contains("messages") || bundleId.contains("telegram") ||
           bundleId.contains("whatsapp") || bundleId.contains("zoom") ||
           bundleId.contains("teams") || bundleId.contains("mail") {
            return .communication
        }
        
        // Productivity
        if bundleId.contains("pages") || bundleId.contains("numbers") ||
           bundleId.contains("keynote") || bundleId.contains("word") ||
           bundleId.contains("excel") || bundleId.contains("powerpoint") {
            return .productivity
        }
        
        // Design
        if bundleId.contains("figma") || bundleId.contains("sketch") ||
           bundleId.contains("photoshop") || bundleId.contains("illustrator") ||
           bundleId.contains("indesign") || bundleId.contains("blender") ||
           bundleId.contains("framer") || bundleId.contains("canva") {
            return .design
        }
        
        return .other
    }
}

/// Information about a UI element
struct ElementInfo: Equatable {
    let role: String
    let title: String?
    let value: String?
    let description: String?
    
    var displayName: String {
        title ?? description ?? role
    }
}

/// File type detection
enum FileType: String {
    case pdf = "PDF"
    case code = "Code"
    case text = "Text"
    case spreadsheet = "Spreadsheet"
    case presentation = "Presentation"
    case image = "Image"
    case video = "Video"
    case webpage = "Web Page"
    case unknown = "Unknown"
    
    static func from(windowTitle: String?) -> FileType {
        guard let title = windowTitle?.lowercased() else { return .unknown }
        
        if title.hasSuffix(".pdf") { return .pdf }
        if title.hasSuffix(".swift") || title.hasSuffix(".py") || 
           title.hasSuffix(".js") || title.hasSuffix(".ts") ||
           title.hasSuffix(".tsx") || title.hasSuffix(".jsx") ||
           title.hasSuffix(".go") || title.hasSuffix(".rs") ||
           title.hasSuffix(".java") || title.hasSuffix(".cpp") ||
           title.hasSuffix(".c") || title.hasSuffix(".h") ||
           title.hasSuffix(".rb") || title.hasSuffix(".php") ||
           title.hasSuffix(".html") || title.hasSuffix(".css") {
            return .code
        }
        if title.hasSuffix(".txt") || title.hasSuffix(".md") ||
           title.hasSuffix(".rtf") || title.hasSuffix(".doc") ||
           title.hasSuffix(".docx") { return .text }
        if title.hasSuffix(".xls") || title.hasSuffix(".xlsx") ||
           title.hasSuffix(".csv") || title.hasSuffix(".numbers") { return .spreadsheet }
        if title.hasSuffix(".ppt") || title.hasSuffix(".pptx") ||
           title.hasSuffix(".key") { return .presentation }
        if title.contains("http://") || title.contains("https://") ||
           title.contains("www.") { return .webpage }
        
        return .unknown
    }
}

/// Complete system context snapshot
struct SystemContext: Equatable {
    let activeApp: AppInfo
    let windowTitle: String?
    let selectedText: String?
    let cursorPosition: CGPoint
    let hoveredElement: ElementInfo?
    let fileType: FileType
    let browserURL: String?
    let timestamp: Date
    
    /// Summary for AI prompt
    var summary: String {
        var parts: [String] = []
        
        parts.append("App: \(activeApp.name) (\(activeApp.category.rawValue))")
        
        if let title = windowTitle, !title.isEmpty {
            parts.append("Window: \(title)")
        }
        
        if fileType != .unknown {
            parts.append("File type: \(fileType.rawValue)")
        }
        
        if let url = browserURL {
            parts.append("URL: \(url)")
        }
        
        if let selected = selectedText, !selected.isEmpty {
            let truncated = selected.count > 200 
                ? String(selected.prefix(200)) + "..." 
                : selected
            parts.append("Selected text: \"\(truncated)\"")
        }
        
        if let element = hoveredElement {
            parts.append("Hovering: \(element.displayName)")
        }
        
        return parts.joined(separator: "\n")
    }
    
    static let empty = SystemContext(
        activeApp: .unknown,
        windowTitle: nil,
        selectedText: nil,
        cursorPosition: .zero,
        hoveredElement: nil,
        fileType: .unknown,
        browserURL: nil,
        timestamp: Date()
    )
}

//
//  ChatHistoryManager.swift
//  screen buddy
//
//  Manages persistence and loading of chat history
//

import Foundation

/// Singleton service for persisting chat history across app sessions
class ChatHistoryManager {
    
    // MARK: - Singleton
    
    static let shared = ChatHistoryManager()
    
    private init() {}
    
    // MARK: - Storage Keys
    
    private let historyStorageKey = "chat_history"
    private let showHistoryKey = "show_history_preference"
    
    // MARK: - Persistence
    
    /// Save chat messages to UserDefaults
    func save(_ messages: [ChatMessage]) {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: historyStorageKey)
            print("💾 Saved \(messages.count) messages to history")
        } catch {
            print("❌ Failed to save chat history: \(error)")
        }
    }
    
    /// Load chat messages from UserDefaults
    func load() -> [ChatMessage] {
        guard let data = UserDefaults.standard.data(forKey: historyStorageKey) else {
            print("📭 No saved chat history found")
            return []
        }
        
        do {
            let messages = try JSONDecoder().decode([ChatMessage].self, from: data)
            print("📂 Loaded \(messages.count) messages from history")
            return messages
        } catch {
            print("❌ Failed to load chat history: \(error)")
            return []
        }
    }
    
    /// Clear all saved history
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyStorageKey)
        print("🗑️ Chat history cleared")
    }
    
    // MARK: - Show History Preference
    
    /// Save show history toggle preference
    func saveShowHistoryPreference(_ show: Bool) {
        UserDefaults.standard.set(show, forKey: showHistoryKey)
    }
    
    /// Load show history toggle preference
    func loadShowHistoryPreference() -> Bool {
        return UserDefaults.standard.bool(forKey: showHistoryKey)
    }
    
    // MARK: - Context Building
    
    /// Build a formatted context string from recent messages for AI context
    /// - Parameters:
    ///   - messages: All chat messages
    ///   - limit: Maximum number of recent messages to include (default: 20)
    /// - Returns: Formatted string suitable for AI context
    func buildContextString(from messages: [ChatMessage], limit: Int = 20) -> String? {
        guard !messages.isEmpty else { return nil }
        
        // Take the most recent messages up to the limit
        let recentMessages = messages.suffix(limit)
        
        var contextLines: [String] = []
        contextLines.append("[Previous conversation]:")
        
        for message in recentMessages {
            let speaker = message.isUser ? "User" : "Buddy"
            // Truncate very long messages to save tokens
            let text = message.text.count > 200 
                ? String(message.text.prefix(200)) + "..." 
                : message.text
            contextLines.append("\(speaker): \(text)")
        }
        
        return contextLines.joined(separator: "\n")
    }
}

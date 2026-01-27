//
//  Conversation.swift
//  screen buddy
//
//  Message and conversation models for AI interaction
//

import Foundation

/// Role of message sender
enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

/// A single message in the conversation
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var context: String? // Optional context summary at time of message
    
    init(role: MessageRole, content: String, context: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.context = context
    }
}

/// AI response with optional behavior instructions
struct AIResponse {
    let text: String
    let expression: RobotExpression?
    let shouldSpeak: Bool
    let action: RobotAction?
    
    init(text: String, expression: RobotExpression? = nil, shouldSpeak: Bool = false, action: RobotAction? = nil) {
        self.text = text
        self.expression = expression
        self.shouldSpeak = shouldSpeak
        self.action = action
    }
}

/// Actions the robot can take
enum RobotAction {
    case nudge(message: String)
    case lookAway
    case hide
    case celebrate
    case think
}

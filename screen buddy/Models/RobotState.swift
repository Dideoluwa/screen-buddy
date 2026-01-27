//
//  RobotState.swift
//  screen buddy
//
//  Robot visual state and expression models
//

import SwiftUI

/// Robot facial expressions
enum RobotExpression: String, CaseIterable {
    case idle
    case thinking
    case happy
    case curious
    case sleeping
    case talking
    case surprised
}

/// Robot's current visual state
@Observable
class RobotState {
    var expression: RobotExpression = .idle
    var isAnimating: Bool = false
    var lookDirection: CGPoint = .zero // -1 to 1 for x and y
    var isTalking: Bool = false
    var isListening: Bool = false
    var onLayoutChange: (() -> Void)?
    
    var showInputBubble: Bool = false {
        didSet { onLayoutChange?() }
    }
    var showResponseBubble: Bool = false {
        didSet { onLayoutChange?() }
    }
    var currentResponse: String = ""
    
    var chatHistory: [ChatMessage] = []
    var showHistory: Bool = false  // Toggle for power users to view chat history
    var isContextAwarenessEnabled: Bool = false  // Opt-in context awareness
    
    // Animation states
    var eyeOpenAmount: CGFloat = 1.0 // 0 = closed, 1 = open
    var breathScale: CGFloat = 1.0
    var bounceOffset: CGFloat = 0
    
    func reset() {
        expression = .idle
        isAnimating = false
        lookDirection = .zero
        isTalking = false
        isListening = false
    }
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date
    
    init(text: String, isUser: Bool, timestamp: Date) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

/// Represents a position anchor on screen
enum ScreenPosition {
    case topLeft, topRight, bottomLeft, bottomRight
    case custom(CGPoint)
    
    var point: CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let padding: CGFloat = 20
        
        switch self {
        case .topLeft:
            return CGPoint(x: screen.minX + padding, y: screen.maxY - padding - 100)
        case .topRight:
            return CGPoint(x: screen.maxX - padding - 100, y: screen.maxY - padding - 100)
        case .bottomLeft:
            return CGPoint(x: screen.minX + padding, y: screen.minY + padding)
        case .bottomRight:
            return CGPoint(x: screen.maxX - padding - 100, y: screen.minY + padding)
        case .custom(let point):
            return point
        }
    }
}

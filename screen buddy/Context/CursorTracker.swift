//
//  CursorTracker.swift
//  screen buddy
//
//  Global cursor position monitoring and hover detection
//

import Foundation
import AppKit
import Combine

/// Tracks cursor position and hover state
@Observable
class CursorTracker {
    
    // MARK: - Properties
    
    var cursorPosition: CGPoint = .zero
    var hoveredElement: ElementInfo?
    var isTracking: Bool = false
    
    // MARK: - Private
    
    private var trackingTimer: Timer?
    private var lastElementCheckTime: Date = .distantPast
    private let elementCheckInterval: TimeInterval = 0.5 // Check hovered element every 0.5s
    private let positionUpdateInterval: TimeInterval = 0.1 // Update position every 0.1s
    
    // MARK: - Singleton
    
    static let shared = CursorTracker()
    
    private init() {}
    
    // MARK: - Start/Stop Tracking
    
    /// Start tracking cursor position
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        trackingTimer = Timer.scheduledTimer(
            withTimeInterval: positionUpdateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updateCursorPosition()
        }
        
        // Make sure timer runs even during UI interactions
        RunLoop.main.add(trackingTimer!, forMode: .common)
    }
    
    /// Stop tracking cursor position
    func stopTracking() {
        isTracking = false
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
    
    // MARK: - Position Updates
    
    private func updateCursorPosition() {
        // Get mouse location in screen coordinates
        let mouseLocation = NSEvent.mouseLocation
        
        // Convert from bottom-left origin to top-left origin for display
        cursorPosition = mouseLocation
        
        // Periodically check what element is under cursor
        if Date().timeIntervalSince(lastElementCheckTime) >= elementCheckInterval {
            checkHoveredElement()
            lastElementCheckTime = Date()
        }
    }
    
    private func checkHoveredElement() {
        // Flip Y coordinate for accessibility API (it uses top-left origin)
        guard let screen = NSScreen.main else { return }
        let flippedY = screen.frame.height - cursorPosition.y
        let flippedPosition = CGPoint(x: cursorPosition.x, y: flippedY)
        
        // Get element at cursor position
        hoveredElement = AccessibilityHandler.shared.getElementAtPosition(flippedPosition)
    }
    
    // MARK: - Cursor Near Robot Detection
    
    /// Check if cursor is near a given rect (for robot interaction)
    func isCursorNear(rect: CGRect, threshold: CGFloat = 50) -> Bool {
        let expandedRect = rect.insetBy(dx: -threshold, dy: -threshold)
        return expandedRect.contains(cursorPosition)
    }
    
    /// Get direction from rect to cursor (for robot eye tracking)
    func directionFromRect(_ rect: CGRect) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        // Calculate direction vector
        let dx = cursorPosition.x - center.x
        let dy = cursorPosition.y - center.y
        
        // Normalize to -1 to 1 range
        let maxDistance: CGFloat = 200
        let normalizedX = max(-1, min(1, dx / maxDistance))
        let normalizedY = max(-1, min(1, dy / maxDistance))
        
        return CGPoint(x: normalizedX, y: normalizedY)
    }
}

//
//  BehaviorManager.swift
//  screen buddy
//
//  Manages robot idle behaviors and random movements
//

import Foundation
import AppKit

/// Manages the robot's idle behaviors and random movements
@Observable
class BehaviorManager {
    
    // MARK: - State
    
    var isActive: Bool = false
    
    // MARK: - Configuration
    
    /// Minimum time between random movements (seconds)
    var minMovementInterval: TimeInterval = 60
    
    /// Maximum time between random movements (seconds)
    var maxMovementInterval: TimeInterval = 180
    
    /// Maximum distance for random movement (pixels)
    var maxMovementDistance: CGFloat = 150
    
    // MARK: - Private
    
    private var movementTimer: Timer?
    private weak var panelController: FloatingPanelController?
    
    // MARK: - Singleton
    
    static let shared = BehaviorManager()
    
    private init() {}
    
    // MARK: - Start/Stop
    
    /// Start idle behaviors
    func start(with panelController: FloatingPanelController) {
        guard !isActive else { 
            print("⚠️ BehaviorManager: Already active, not starting again")
            return 
        }
        
        self.panelController = panelController
        isActive = true
        
        print("🤖 Behavior manager started!")
        print("   - panelController: \(panelController)")
        print("   - panelController position: \(panelController.position)")
        print("   - First movement in 2 seconds...")
        
        // Trigger an initial movement after a short delay to show the robot is alive
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            print("⏰ Initial movement timer fired!")
            self?.performRandomMovement()
        }
        
        scheduleNextMovement()
    }
    
    /// Stop idle behaviors
    func stop() {
        isActive = false
        movementTimer?.invalidate()
        movementTimer = nil
        
        print("🤖 Behavior manager stopped")
    }
    
    // MARK: - Random Movement
    
    private func scheduleNextMovement() {
        guard isActive else { 
            print("⚠️ BehaviorManager: Not scheduling - isActive is false")
            return 
        }
        
        let interval = TimeInterval.random(in: minMovementInterval...maxMovementInterval)
        print("⏰ BehaviorManager: Scheduling next movement in \(String(format: "%.1f", interval)) seconds")
        
        // Use DispatchQueue for more reliable timing
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self = self, self.isActive else {
                print("⚠️ BehaviorManager: Timer fired but manager is inactive or deallocated")
                return
            }
            print("⏰ BehaviorManager: Timer fired!")
            self.performRandomMovement()
        }
    }
    
    private func performRandomMovement() {
        print("🔄 performRandomMovement() called")
        
        guard isActive else {
            print("❌ BehaviorManager: isActive is false")
            scheduleNextMovement()
            return
        }
        
        guard let panelController = panelController else {
            print("❌ BehaviorManager: panelController is nil! Movement impossible.")
            scheduleNextMovement()
            return
        }
        
        print("✅ BehaviorManager: panelController is valid")
        
        // Don't move if user is interacting
        if panelController.isDragging {
            print("⏸️ BehaviorManager: Skipping - user is dragging")
            scheduleNextMovement()
            return
        }
        
        if panelController.robotState.showInputBubble {
            print("⏸️ BehaviorManager: Skipping - input bubble is shown")
            scheduleNextMovement()
            return
        }
        
        if panelController.robotState.showResponseBubble {
            print("⏸️ BehaviorManager: Skipping - response bubble is shown")
            scheduleNextMovement()
            return
        }
        
        // Always move now (removed random chance for debugging)
        print("✅ BehaviorManager: Proceeding with movement")
        
        // Calculate random offset with minimum distance for noticeable movement
        let minDistance: CGFloat = 100
        var offsetX = CGFloat.random(in: -maxMovementDistance...maxMovementDistance)
        var offsetY = CGFloat.random(in: -maxMovementDistance...maxMovementDistance)
        
        // Ensure minimum movement distance
        if abs(offsetX) < minDistance {
            offsetX = offsetX >= 0 ? minDistance : -minDistance
        }
        if abs(offsetY) < minDistance {
            offsetY = offsetY >= 0 ? minDistance : -minDistance
        }
        
        // Get current position and calculate new position
        let currentPosition = panelController.position
        var newPosition = CGPoint(
            x: currentPosition.x + offsetX,
            y: currentPosition.y + offsetY
        )
        
        // Keep within screen bounds (use full screen frame, not visible frame)
        if let screen = NSScreen.main?.frame {
            let panelWidth: CGFloat = panelController.panelFrame?.width ?? 140
            let panelHeight: CGFloat = panelController.panelFrame?.height ?? 140
            newPosition.x = max(screen.minX, min(screen.maxX - panelWidth, newPosition.x))
            newPosition.y = max(screen.minY, min(screen.maxY - panelHeight, newPosition.y))
        }
        
        // Perform animated movement
        animateMovement(to: newPosition)
        
        // Schedule next movement
        scheduleNextMovement()
    }
    
    private func animateMovement(to newPosition: CGPoint) {
        guard let panelController = panelController else { 
            print("⚠️ Panel controller is nil - cannot animate")
            return 
        }
        
        let currentPos = panelController.position
        print("🚀 Moving robot from (\(Int(currentPos.x)), \(Int(currentPos.y))) to (\(Int(newPosition.x)), \(Int(newPosition.y)))")
        
        // Show curious expression during movement
        DispatchQueue.main.async {
            panelController.robotState.expression = .curious
        }
        
        // Animate position change (must be on main thread)
        DispatchQueue.main.async {
            panelController.animateToPosition(newPosition, duration: 0.8)
        }
        
        // Reset expression after movement
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak panelController] in
            if panelController?.robotState.expression == .curious {
                panelController?.robotState.expression = .idle
            }
        }
    }
    
    // MARK: - Manual Triggers
    
    /// Trigger an immediate random movement
    func triggerRandomMovement() {
        movementTimer?.invalidate()
        performRandomMovement()
    }
    
    /// Make the robot "look around" (change eye direction randomly)
    func triggerLookAround() {
        guard let panelController = panelController else { return }
        
        let randomX = CGFloat.random(in: -1...1)
        let randomY = CGFloat.random(in: -0.5...0.5)
        
        DispatchQueue.main.async {
            panelController.robotState.lookDirection = CGPoint(x: randomX, y: randomY)
        }
        
        // Reset after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak panelController] in
            panelController?.robotState.lookDirection = .zero
        }
    }
}

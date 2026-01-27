//
//  FloatingPanel.swift
//  screen buddy
//
//  Custom NSPanel that stays on top and doesn't steal focus
//

import AppKit
import SwiftUI

/// A borderless, transparent floating panel that stays above all windows
class FloatingPanel: NSPanel {
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel], backing backingStoreType: NSWindow.BackingStoreType = .buffered, defer flag: Bool = false) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        configure()
    }
    
    private func configure() {
        // Floating behavior - use screenSaver level for maximum visibility
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        
        // Transparency
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        
        // Don't show in mission control, don't hide on deactivate
        hidesOnDeactivate = false
        
        // Allow interaction but don't become key window unless needed
        isMovableByWindowBackground = false
        
        // Accept mouse events
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
    }
    
    // Only become key when explicitly requested (for text input)
    override var canBecomeKey: Bool {
        return true
    }
    
    // Never become main window
    override var canBecomeMain: Bool {
        return false
    }
}

/// Controller for managing the floating robot panel
class FloatingPanelController: NSObject, ObservableObject {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var eyeTrackingTimer: Timer?
    
    @Published var position: CGPoint = ScreenPosition.bottomRight.point
    @Published var isDragging: Bool = false
    
    let robotState = RobotState()
    
    // Reference to context engine for robot awareness
    let contextEngine = ContextEngine.shared
    
    override init() {
        super.init()
        
        // Load persist chat history and preferences
        let historyManager = ChatHistoryManager.shared
        robotState.chatHistory = historyManager.load()
        robotState.showHistory = historyManager.loadShowHistoryPreference()
        print("📂 Restored \(robotState.chatHistory.count) messages and showHistory=\(robotState.showHistory)")
        
        // Listen for layout changes
        robotState.onLayoutChange = { [weak self] in
            DispatchQueue.main.async {
                self?.updatePanelLayout()
            }
        }
    }
    
    /// Updates panel size based on content state
    /// Updates panel size based on content state
    private func updatePanelLayout() {
        guard let panel = panel else { return }
        
        // Determine target state
        let isExpanded = robotState.showInputBubble || robotState.showResponseBubble || robotState.showHistory
        
        let targetSize = isExpanded ? CGSize(width: 350, height: 600) : CGSize(width: 140, height: 140)
        
        // Skip if already at target size
        if panel.frame.size == targetSize { return }
        
        // Logic:
        // - Expanding: Do it immediately so content has room to appear
        // - Shrinking: Delay slightly so SwiftUI exit transition finishes first
        let delay = isExpanded ? 0.0 : 0.35
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let panel = self.panel else { return }
            
            // Re-check state just in case it changed during delay
            let currentExpandedState = self.robotState.showInputBubble || self.robotState.showResponseBubble || self.robotState.showHistory
            let currentTargetSize = currentExpandedState ? CGSize(width: 350, height: 600) : CGSize(width: 140, height: 140)
            
            let currentFrame = panel.frame
            
            // Calculate new origin to keep bottom-center fixed
            let widthDiff = currentTargetSize.width - currentFrame.width
            var newX = currentFrame.minX - (widthDiff / 2)
            let newY = currentFrame.minY
            
            // Clamp to screen
            if let screen = NSScreen.main?.frame {
                newX = max(screen.minX, min(screen.maxX - currentTargetSize.width, newX))
            }
            
            let newFrame = NSRect(origin: CGPoint(x: newX, y: newY), size: currentTargetSize)
            
            print("📏 Resizing panel to \(currentExpandedState ? "Expanded" : "Compact"): \(currentTargetSize) (Delay: \(delay)s)")
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(newFrame, display: true)
            }
            
            self.position = newFrame.origin
            self.hostingView?.frame = NSRect(origin: .zero, size: currentTargetSize)
        }
    }
    
    /// Start eye tracking (robot looks toward cursor)
    func startEyeTracking() {
        eyeTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateEyeDirection()
        }
        RunLoop.main.add(eyeTrackingTimer!, forMode: .common)
    }
    
    func stopEyeTracking() {
        eyeTrackingTimer?.invalidate()
        eyeTrackingTimer = nil
    }
    
    private func updateEyeDirection() {
        guard let frame = panelFrame else { return }
        let direction = CursorTracker.shared.directionFromRect(frame)
        robotState.lookDirection = direction
    }
    
    /// Creates and shows the floating panel with the robot view
    func showPanel<Content: View>(@ViewBuilder content: () -> Content) {
        let panelSize = CGSize(width: 350, height: 600) // Increased vertical space for chat
        
        // Calculate a visible starting position
        if let screen = NSScreen.main?.visibleFrame {
            let padding: CGFloat = 50
            position = CGPoint(
                x: screen.maxX - panelSize.width - padding,
                y: screen.minY + padding + 50
            )
        }
        
        let contentRect = NSRect(
            origin: position,
            size: panelSize
        )
        
        panel = FloatingPanel(contentRect: contentRect)
        
        let wrappedContent = AnyView(
            content()
                .environmentObject(self)
        )
        
        hostingView = NSHostingView(rootView: wrappedContent)
        hostingView?.frame = NSRect(origin: .zero, size: panelSize)
        
        // CRITICAL: Ensure the hosting view uses layers for proper rendering
        hostingView?.wantsLayer = true
        hostingView?.layer?.backgroundColor = NSColor.clear.cgColor
        
        panel?.contentView = hostingView
        
        // Make sure panel is visible and on screen
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        
        // Start eye tracking
        startEyeTracking()
        
        // Set initial correct size based on state
        updatePanelLayout()
        
        print("🤖 Robot panel shown at position: \(position)")
        print("📐 Panel frame: \(panel?.frame ?? .zero)")
        print("👁️ Panel isVisible: \(panel?.isVisible ?? false)")
    }
    
    /// Updates the panel position
    func updatePosition(_ newPosition: CGPoint) {
        position = newPosition
        panel?.setFrameOrigin(newPosition)
    }
    
    /// Handle drag gesture
    func handleDrag(translation: CGSize) {
        guard let panel = panel else { return }
        
        let currentOrigin = panel.frame.origin
        let newOrigin = CGPoint(
            x: currentOrigin.x + translation.width,
            y: currentOrigin.y - translation.height // Flip Y for screen coordinates
        )
        
        panel.setFrameOrigin(newOrigin)
        position = newOrigin
    }
    
    /// Snap to nearest screen edge
    func snapToEdge() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        
        let centerX = position.x + 50 // Approximate panel center
        let centerY = position.y + 50
        
        let padding: CGFloat = 20
        
        // Determine closest edge
        let distanceToLeft = centerX - screen.minX
        let distanceToRight = screen.maxX - centerX
        let distanceToTop = screen.maxY - centerY
        let distanceToBottom = centerY - screen.minY
        
        var newPosition = position
        
        // Snap horizontally
        if distanceToLeft < distanceToRight {
            newPosition.x = screen.minX + padding
        } else {
            newPosition.x = screen.maxX - padding - 100
        }
        
        // Keep within vertical bounds
        newPosition.y = max(screen.minY + padding, min(screen.maxY - padding - 100, newPosition.y))
        
        // Animate to new position
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().setFrameOrigin(newPosition)
        }
        
        position = newPosition
    }
    
    /// Hide the panel
    func hidePanel() {
        panel?.orderOut(nil)
    }
    
    /// Show the panel if hidden
    func showPanel() {
        panel?.orderFrontRegardless()
    }
    
    /// Get current panel frame
    var panelFrame: NSRect? {
        return panel?.frame
    }
    
    /// Animate to a new position with custom duration
    func animateToPosition(_ newPosition: CGPoint, duration: TimeInterval = 0.5) {
        guard let panel = panel else { 
            print("⚠️ FloatingPanel: panel is nil, cannot animate")
            return 
        }
        
        // Ensure within screen bounds (use full screen frame)
        var boundedPosition = newPosition
        if let screen = NSScreen.main?.frame {
            let panelWidth: CGFloat = panel.frame.width
            let panelHeight: CGFloat = panel.frame.height
            boundedPosition.x = max(screen.minX, min(screen.maxX - panelWidth, boundedPosition.x))
            boundedPosition.y = max(screen.minY, min(screen.maxY - panelHeight, boundedPosition.y))
        }
        
        let startPosition = panel.frame.origin
        let deltaX = boundedPosition.x - startPosition.x
        let deltaY = boundedPosition.y - startPosition.y
        
        print("🎬 FloatingPanel: Animating from (\(Int(startPosition.x)), \(Int(startPosition.y))) to (\(Int(boundedPosition.x)), \(Int(boundedPosition.y))) over \(duration)s")
        
        // Use a timer-based animation for reliable NSPanel movement
        let steps = 30
        let stepDuration = duration / Double(steps)
        var currentStep = 0
        
        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            currentStep += 1
            let progress = Double(currentStep) / Double(steps)
            
            // Ease-in-out timing function
            let easedProgress = progress < 0.5 
                ? 2 * progress * progress 
                : 1 - pow(-2 * progress + 2, 2) / 2
            
            let newX = startPosition.x + deltaX * easedProgress
            let newY = startPosition.y + deltaY * easedProgress
            
            DispatchQueue.main.async {
                panel.setFrameOrigin(CGPoint(x: newX, y: newY))
            }
            
            if currentStep >= steps {
                timer.invalidate()
                DispatchQueue.main.async {
                    panel.setFrameOrigin(boundedPosition)
                    self?.position = boundedPosition
                    print("✅ FloatingPanel: Animation complete")
                }
            }
        }
    }
}

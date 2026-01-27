import Foundation
import AppKit

/// Tracks user interaction (Mouse, Keyboard) to determine "Idle" vs "Active" state.
/// Does NOT log keystrokes, only activity timestamps.
class InteractionMonitor: ObservableObject {
    
    // MARK: - Published State
    @Published var interactionState: String = "Idle" // "Active", "Reading", "Idle", "Watching"
    @Published var lastInteractionTime: Date = Date()
    
    private var eventMonitor: Any?
    private var activityTimer: Timer?
    
    // MARK: - Lifecycle
    
    func startMonitoring() {
        print("🖱️ Interaction: Started Monitoring")
        
        // 1. Global Event Monitor (Mouse Move, Click, Key Down, Scroll)
        // Note: functionality requires Accessibility permissions to work globally.
        // If not granted, it might only work when app is focused (which is fine for dev, but needs permission for prod).
        
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.recordActivity()
        }
        
        // 2. Local Monitor (for when our app is active)
        NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.recordActivity()
            return event
        }
        
        // 3. State loop (Check status every 1s)
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateState()
        }
    }
    
    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        activityTimer?.invalidate()
        activityTimer = nil
    }
    
    // MARK: - Logic
    
    private func recordActivity() {
        lastInteractionTime = Date()
        if interactionState == "Idle" || interactionState == "Watching" {
            DispatchQueue.main.async {
                self.interactionState = "Active"
            }
        }
    }
    
    private func updateState() {
        let timeSinceLast = Date().timeIntervalSince(lastInteractionTime)
        
        var newState = interactionState
        
        // Logic:
        // < 5s: Active
        // 5s - 30s: Reading / Thinking
        // > 30s: Idle / Watching (if video playing)
        
        if timeSinceLast < 5 {
            newState = "Active"
        } else if timeSinceLast < 30 {
            newState = "Reading"
        } else {
            newState = "Idle"
        }
        
        if interactionState != newState {
            DispatchQueue.main.async {
                self.interactionState = newState
            }
        }
    }
}

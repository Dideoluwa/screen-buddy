import Foundation
import ScreenCaptureKit
import AppKit

/// Tracks the Active Application and Window Title.
/// Uses NSWorkspace for app focus and ScreenCaptureKit for window details.
class MetadataMonitor: ObservableObject {
    
    // MARK: - Published State
    @Published var activeApp: String = "Unknown"
    @Published var activeBundleId: String? = nil
    @Published var windowTitle: String = "Unknown"
    
    private var timer: Timer?
    
    // MARK: - Lifecycle
    
    init() {
        // Observers for App Switching (Instant)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    func startMonitoring() {
        print("👀 Metadata: Started Monitoring")
        // Initial fetch
        updateMetadata()
        
        // Poll for window title changes (every 2s is sufficient)
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateMetadata()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Logic
    
    @objc private func appDidActivate(_ notification: Notification) {
        // Immediate update on app switch
        updateMetadata()
    }
    
    private func updateMetadata() {
        Task { @MainActor in
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
            
            // 1. Update App Name
            if self.activeApp != frontApp.localizedName {
                self.activeApp = frontApp.localizedName ?? "Unknown"
                self.activeBundleId = frontApp.bundleIdentifier
            }
            
            // 2. Fetch Window Title via ScreenCaptureKit
            // This is heavier, so we only do it if necessary or periodically
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                
                // Find the main window of the active app
                // Criteria: Belong to frontApp + On Screen + Highest z-order (first in list usually)
                if let window = content.windows.first(where: {
                    $0.owningApplication?.bundleIdentifier == frontApp.bundleIdentifier &&
                    $0.isOnScreen &&
                    $0.title != "" // Filter empty titles
                }) {
                    if self.windowTitle != window.title {
                        self.windowTitle = window.title ?? "Unknown"
                        // print("🪟 Window: \(self.windowTitle)")
                    }
                }
            } catch {
                print("❌ Metadata Error: \(error.localizedDescription)")
            }
        }
    }
}

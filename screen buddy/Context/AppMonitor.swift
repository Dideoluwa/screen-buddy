//
//  AppMonitor.swift
//  screen buddy
//
//  Monitors active application changes and extracts app metadata
//

import Foundation
import AppKit
import Combine

/// Monitors the frontmost application and window
@Observable
class AppMonitor {
    
    // MARK: - Properties
    
    var currentApp: AppInfo = .unknown
    var currentWindowTitle: String?
    var isMonitoring: Bool = false
    
    // MARK: - Private
    
    private var workspaceObserver: Any?
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 1.0 // Check window title every second
    
    // MARK: - Singleton
    
    static let shared = AppMonitor()
    
    private init() {}
    
    // MARK: - Start/Stop Monitoring
    
    /// Start monitoring app changes
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // Initial update
        updateCurrentApp()
        
        // Observe app activation
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
        
        // Timer for window title updates (titles can change without app change)
        updateTimer = Timer.scheduledTimer(
            withTimeInterval: updateInterval,
            repeats: true
        ) { [weak self] _ in
            self?.updateWindowTitle()
        }
        RunLoop.main.add(updateTimer!, forMode: .common)
    }
    
    /// Stop monitoring app changes
    func stopMonitoring() {
        isMonitoring = false
        
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - App Detection
    
    private func handleAppActivation(_ notification: Notification) {
        updateCurrentApp()
    }
    
    private func updateCurrentApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            currentApp = .unknown
            return
        }
        
        let bundleId = app.bundleIdentifier
        let category = AppCategory.from(bundleId: bundleId)
        
        currentApp = AppInfo(
            name: app.localizedName ?? "Unknown",
            bundleIdentifier: bundleId,
            category: category,
            isActive: true
        )
        
        // Also update window title
        updateWindowTitle()
    }
    
    private func updateWindowTitle() {
        // Try accessibility first
        if let title = AccessibilityHandler.shared.getFrontmostWindowTitle() {
            currentWindowTitle = title
            return
        }
        
        // Fallback: get from running app
        if let app = NSWorkspace.shared.frontmostApplication {
            // For some apps, the app name is a reasonable fallback
            currentWindowTitle = app.localizedName
        }
    }
    
    // MARK: - Context Helpers
    
    /// Get file type from current window title
    var currentFileType: FileType {
        return FileType.from(windowTitle: currentWindowTitle)
    }
    
    /// Check if current app is a browser
    var isBrowser: Bool {
        return currentApp.category == .browser
    }
    
    /// Check if current app is a code editor
    var isCodeEditor: Bool {
        return currentApp.category == .codeEditor
    }
    
    /// Check if current app is media-related
    var isMediaApp: Bool {
        return currentApp.category == .mediaPlayer || currentApp.category == .videoStreaming
    }
    
    /// Check if user is likely watching content (media apps or browser with video)
    var isWatchingContent: Bool {
        if currentApp.category == .videoStreaming || currentApp.category == .mediaPlayer {
            return true
        }
        
        // Check if browser with video site
        if isBrowser {
            if let title = currentWindowTitle?.lowercased() {
                return title.contains("youtube") || 
                       title.contains("netflix") ||
                       title.contains("video") ||
                       title.contains("watch")
            }
        }
        
        return false
    }
}

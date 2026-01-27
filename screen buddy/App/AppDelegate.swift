//
//  AppDelegate.swift
//  screen buddy
//
//  App lifecycle management and floating panel setup
//

import AppKit
import SwiftUI

/// Main app delegate handling window and panel management
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    
    // Context engine for system awareness
    private let contextEngine = ContextEngine.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (we're a floating companion, not a regular app)
        NSApp.setActivationPolicy(.accessory)
        
        // Create panel controller
        panelController = FloatingPanelController()
        
        // Register with InteractionManager
        if let pc = panelController {
            InteractionManager.shared.setPanelController(pc)
        }
        
        // Show the floating robot panel
        panelController?.showPanel {
            RobotView()
        }
        
        // Create menu bar status item
        setupStatusItem()
        
        // Check permissions on launch
        checkPermissions()
        
        // Start context engine after a short delay (to allow permissions)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // ContextEngine is started in screen_buddyApp.init()
            // No need to start it again here
            self?.startBehaviorManager()
            NudgeManager.shared.start()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NudgeManager.shared.stop()
        BehaviorManager.shared.stop()
        contextEngine.stop()
        panelController?.hidePanel()
    }
    
    // MARK: - Behavior Manager
    
    private func startBehaviorManager() {
        guard let panelController = panelController else { return }
        BehaviorManager.shared.start(with: panelController)
    }
    
    // MARK: - Context Engine
    
    private func startContextEngine() {
        guard PermissionManager.shared.accessibilityGranted else {
            print("⚠️ Context engine not started: Accessibility permission not granted")
            return
        }
        
        contextEngine.start()
        print("✅ Context engine started")
        
        // Log context updates for debugging
        #if DEBUG
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            let context = ContextEngine.shared.currentContext
            print("📍 Context Update:")
            print("   App: \(context.activeApp.name) (\(context.activeApp.category.rawValue))")
            if let title = context.windowTitle {
                print("   Window: \(title)")
            }
            if let selected = context.selectedText {
                print("   Selected: \(selected.prefix(50))...")
            }
            if let url = context.browserURL {
                print("   URL: \(url)")
            }
        }
        #endif
    }
    
    // MARK: - Status Item
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Use SF Symbol for menu bar
            button.image = NSImage(systemSymbolName: "face.smiling.inverse", accessibilityDescription: "Screen Buddy")
            button.image?.size = NSSize(width: 18, height: 18)
        }
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Show Robot", action: #selector(showRobot), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Hide Robot", action: #selector(hideRobot), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        
        // Context status submenu
        let contextItem = NSMenuItem(title: "Context Status", action: nil, keyEquivalent: "")
        let contextMenu = NSMenu()
        contextMenu.addItem(NSMenuItem(title: "Refresh Context", action: #selector(refreshContext), keyEquivalent: "r"))
        contextMenu.addItem(NSMenuItem(title: "Show Current Context", action: #selector(showContext), keyEquivalent: ""))
        contextItem.submenu = contextMenu
        menu.addItem(contextItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Screen Buddy", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func showRobot() {
        panelController?.showPanel()
    }
    
    @objc private func hideRobot() {
        panelController?.hidePanel()
    }
    
    @objc private func refreshContext() {
        let context = contextEngine.forceRefresh()
        print("🔄 Context refreshed: \(context.activeApp.name)")
    }
    
    @objc private func showContext() {
        let context = contextEngine.currentContext
        let alert = NSAlert()
        alert.messageText = "Current Context"
        alert.informativeText = context.summary
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func openSettings() {
        // Open the Settings scene
        if #available(macOS 14.0, *) {
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Permissions
    
    private func checkPermissions() {
        PermissionManager.shared.checkAllPermissions()
        
        if !PermissionManager.shared.accessibilityGranted {
            PermissionManager.shared.requestAccessibility()
        }
    }
}

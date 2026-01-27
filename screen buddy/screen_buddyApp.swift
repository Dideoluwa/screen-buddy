//
//  screen_buddyApp.swift
//  screen buddy
//
//  Main app entry point
//

import SwiftUI

@main
struct screen_buddyApp: App {
    // Use AppDelegate for panel management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Initialize ContextEngine (it's opt-in now - doesn't auto-start)
        _ = ContextEngine.shared
    }
    
    var body: some Scene {
        // Settings scene for preferences window
        Settings {
            SettingsView()
        }
    }
}

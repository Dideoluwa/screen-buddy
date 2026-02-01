//
//  OpenAppTool.swift
//  screen buddy
//
//  Tool for launching macOS applications
//

import Foundation
import AppKit

/// Tool that opens/launches macOS applications
class OpenAppTool: BaseAgentTool {
    
    init() {
        super.init(
            name: "open_app",
            description: "Opens a macOS application by name",
            parameterSchema: [
                "app": "Name of the application to open (e.g., 'Google Chrome', 'Safari', 'Terminal')"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let appName = try requireParam("app", from: params)
        
        print("🚀 OpenAppTool: Opening \(appName)...")
        
        // Try different approaches to open the app
        let workspace = NSWorkspace.shared
        
        // Method 1: Try opening by name directly
        if workspace.launchApplication(appName) {
            // Wait a moment for the app to actually launch
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Verify it opened
            if let app = NSWorkspace.shared.runningApplications.first(where: { 
                $0.localizedName?.lowercased() == appName.lowercased() 
            }) {
                return "Successfully opened \(app.localizedName ?? appName). App is now active."
            }
            
            return "Launched \(appName). Application should now be open."
        }
        
        // Method 2: Try common bundle identifiers
        let bundleId = guessBundleIdentifier(for: appName)
        if let bundleId = bundleId {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                try await workspace.openApplication(at: appURL, configuration: config)
                try? await Task.sleep(nanoseconds: 500_000_000)
                return "Successfully opened \(appName) via bundle identifier."
            }
        }
        
        // Method 3: Try opening via /Applications folder
        let appPath = "/Applications/\(appName).app"
        if FileManager.default.fileExists(atPath: appPath) {
            let appURL = URL(fileURLWithPath: appPath)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            
            try await workspace.openApplication(at: appURL, configuration: config)
            try? await Task.sleep(nanoseconds: 500_000_000)
            return "Successfully opened \(appName) from Applications folder."
        }
        
        // Method 4: Try with shell command as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            return "Opened \(appName) using system open command."
        }
        
        throw AgentError.stepExecutionFailed("Could not open application: \(appName). Make sure the app is installed.")
    }
    
    /// Guess common bundle identifiers for popular apps
    private func guessBundleIdentifier(for appName: String) -> String? {
        let name = appName.lowercased()
        
        let knownApps: [String: String] = [
            "google chrome": "com.google.Chrome",
            "chrome": "com.google.Chrome",
            "safari": "com.apple.Safari",
            "terminal": "com.apple.Terminal",
            "finder": "com.apple.finder",
            "mail": "com.apple.mail",
            "messages": "com.apple.MobileSMS",
            "notes": "com.apple.Notes",
            "calendar": "com.apple.iCal",
            "reminders": "com.apple.reminders",
            "music": "com.apple.Music",
            "photos": "com.apple.Photos",
            "preview": "com.apple.Preview",
            "textedit": "com.apple.TextEdit",
            "calculator": "com.apple.calculator",
            "system preferences": "com.apple.systempreferences",
            "system settings": "com.apple.systempreferences",
            "app store": "com.apple.AppStore",
            "xcode": "com.apple.dt.Xcode",
            "visual studio code": "com.microsoft.VSCode",
            "vscode": "com.microsoft.VSCode",
            "slack": "com.tinyspeck.slackmacgap",
            "spotify": "com.spotify.client",
            "discord": "com.hnc.Discord",
            "zoom": "us.zoom.xos",
            "firefox": "org.mozilla.firefox",
            "arc": "company.thebrowser.Browser"
        ]
        
        return knownApps[name]
    }
}

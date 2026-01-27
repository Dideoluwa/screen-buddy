//
//  AccessibilityHandler.swift
//  screen buddy
//
//  Wrapper for macOS Accessibility APIs to extract UI context
//

import Foundation
import AppKit
import ApplicationServices

/// Handles all Accessibility API interactions
class AccessibilityHandler {
    
    // MARK: - Singleton
    
    static let shared = AccessibilityHandler()
    
    private init() {}
    
    // MARK: - Permission
    
    /// Check if accessibility is enabled
    var isAccessibilityEnabled: Bool {
        return AXIsProcessTrusted()
    }
    
    // MARK: - Focused Element
    
    /// Get the currently focused UI element
    func getFocusedElement() -> ElementInfo? {
        guard isAccessibilityEnabled else { return nil }
        
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        
        return extractElementInfo(from: element as! AXUIElement)
    }
    
    // MARK: - Selected Text
    
    /// Get currently selected text from the focused element
    func getSelectedText() -> String? {
        guard isAccessibilityEnabled else { return nil }
        
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        
        // Try to get selected text
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        
        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }
        
        return nil
    }
    
    // MARK: - Element at Position
    
    /// Get the UI element at a specific screen position
    func getElementAtPosition(_ position: CGPoint) -> ElementInfo? {
        guard isAccessibilityEnabled else { return nil }
        
        let systemWide = AXUIElementCreateSystemWide()
        
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(position.x),
            Float(position.y),
            &element
        )
        
        guard result == .success, let foundElement = element else {
            return nil
        }
        
        return extractElementInfo(from: foundElement)
    }
    
    // MARK: - Window Information
    
    /// Get the frontmost window title
    func getFrontmostWindowTitle() -> String? {
        guard isAccessibilityEnabled else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Get focused window
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
        
        guard result == .success, let window = focusedWindow else {
            // Try main window instead
            var mainWindow: CFTypeRef?
            let mainResult = AXUIElementCopyAttributeValue(
                appElement,
                kAXMainWindowAttribute as CFString,
                &mainWindow
            )
            
            if mainResult == .success, let mw = mainWindow {
                return getWindowTitle(from: mw as! AXUIElement)
            }
            return nil
        }
        
        return getWindowTitle(from: window as! AXUIElement)
    }
    
    /// Get all window titles for the frontmost app
    func getAllWindowTitles() -> [String] {
        guard isAccessibilityEnabled else { return [] }
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windows
        )
        
        guard result == .success, let windowList = windows as? [AXUIElement] else {
            return []
        }
        
        return windowList.compactMap { getWindowTitle(from: $0) }
    }
    
    // MARK: - Browser URL
    
    /// Try to get the current URL from Safari or Chrome
    func getBrowserURL() -> String? {
        guard isAccessibilityEnabled else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let bundleId = app.bundleIdentifier?.lowercased() ?? ""
        
        // Safari
        if bundleId.contains("safari") {
            return getSafariURL()
        }
        
        // Chrome, Brave, Edge (Chromium-based)
        if bundleId.contains("chrome") || bundleId.contains("brave") || bundleId.contains("edge") {
            return getChromiumURL(for: app)
        }
        
        // Arc
        if bundleId.contains("arc") {
            return getArcURL(for: app)
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    private func extractElementInfo(from element: AXUIElement) -> ElementInfo {
        var role: CFTypeRef?
        var title: CFTypeRef?
        var value: CFTypeRef?
        var description: CFTypeRef?
        
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        
        return ElementInfo(
            role: (role as? String) ?? "Unknown",
            title: title as? String,
            value: (value as? String)?.prefix(100).description, // Limit value length
            description: description as? String
        )
    }
    
    private func getWindowTitle(from window: AXUIElement) -> String? {
        var title: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &title
        )
        
        if result == .success, let titleString = title as? String {
            return titleString
        }
        return nil
    }
    
    private func getSafariURL() -> String? {
        // Use AppleScript for Safari (most reliable)
        let script = """
        tell application "Safari"
            if (count of windows) > 0 then
                return URL of current tab of window 1
            end if
        end tell
        """
        
        return runAppleScript(script)
    }
    
    private func getChromiumURL(for app: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        // Navigate to: App -> Window -> Toolbar -> TextField (address bar)
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .success,
              let windowList = windows as? [AXUIElement],
              let mainWindow = windowList.first else {
            return nil
        }
        
        // Search for URL bar in the window hierarchy
        return findURLBar(in: mainWindow)
    }
    
    private func getArcURL(for app: NSRunningApplication) -> String? {
        // Arc has a specific structure, try accessibility first
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .success,
              let windowList = windows as? [AXUIElement],
              let mainWindow = windowList.first else {
            return nil
        }
        
        return findURLBar(in: mainWindow)
    }
    
    private func findURLBar(in element: AXUIElement, depth: Int = 0) -> String? {
        // Prevent infinite recursion
        guard depth < 10 else { return nil }
        
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        // Look for text fields with URL-like content
        if let roleStr = role as? String, roleStr == "AXTextField" || roleStr == "AXComboBox" {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
               let urlString = value as? String,
               (urlString.contains("http") || urlString.contains(".com") || urlString.contains(".org")) {
                return urlString
            }
        }
        
        // Recursively search children
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childList = children as? [AXUIElement] else {
            return nil
        }
        
        for child in childList {
            if let url = findURLBar(in: child, depth: depth + 1) {
                return url
            }
        }
        
        return nil
    }
    
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        
        let result = script.executeAndReturnError(&error)
        
        if error == nil {
            return result.stringValue
        }
        return nil
    }
}

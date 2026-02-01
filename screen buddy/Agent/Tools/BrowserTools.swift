//
//  BrowserTools.swift
//  screen buddy
//
//  Browser automation tools for visible typing, scrolling, and clicking
//

import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Browser Navigate Tool

/// Navigate browser to a URL
class BrowserNavigateTool: BaseAgentTool {
    init() {
        super.init(
            name: "browser_navigate",
            description: "Navigate the browser to a URL",
            parameterSchema: [
                "url": "The URL to navigate to"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let url = try requireParam("url", from: params)
        
        // Use AppleScript to open URL in default browser
        let script = """
        tell application "System Events"
            open location "\(url)"
        end tell
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        try process.run()
        process.waitUntilExit()
        
        // Wait for page to load
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
        
        return "Navigated to \(url)"
    }
}

// MARK: - Browser Type Tool

/// Type text visibly in the browser, character by character
class BrowserTypeTool: BaseAgentTool {
    init() {
        super.init(
            name: "browser_type",
            description: "Type text in the frontmost app with visible human-like keystrokes",
            parameterSchema: [
                "text": "The text to type",
                "delay_ms": "Optional delay between keystrokes in ms (default: 100 for human-like speed)"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let text = try requireParam("text", from: params)
        let delayMs = Int(params["delay_ms"] ?? "100") ?? 100  // 100ms = human-like speed
        
        print("⌨️ Typing visibly: '\(text)'")
        
        // Type each character with delay for visibility
        for char in text {
            simulateKeyPress(char)
            try await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
        }
        
        return "Typed: \(text)"
    }
    
    private func simulateKeyPress(_ char: Character) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Get key code for character
        guard let keyCode = keyCodeForChar(char) else {
            print("⚠️ No key code for: \(char)")
            return
        }
        
        let needsShift = char.isUppercase || shiftRequired(char)
        
        // Key down
        if needsShift {
            let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(56), keyDown: true)
            shiftDown?.post(tap: .cghidEventTap)
        }
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.post(tap: .cghidEventTap)
        
        // Key up
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.post(tap: .cghidEventTap)
        
        if needsShift {
            let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(56), keyDown: false)
            shiftUp?.post(tap: .cghidEventTap)
        }
    }
    
    private func keyCodeForChar(_ char: Character) -> CGKeyCode? {
        // Key codes for US keyboard layout
        let charToKeyCode: [Character: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
            " ": 49, "\n": 36, "\t": 48
        ]
        
        // Characters that map to same key with shift
        let shiftCharToBaseChar: [Character: Character] = [
            ":": ";",  // Shift + ; = :
            "?": "/",  // Shift + / = ?
            "+": "=",  // Shift + = = +
            "!": "1",
            "@": "2",
            "#": "3",
            "$": "4",
            "%": "5",
            "^": "6",
            "&": "7",
            "*": "8",
            "(": "9",
            ")": "0",
            "_": "-",
            "{": "[",
            "}": "]",
            "|": "\\",
            "\"": "'",
            "<": ",",
            ">": ".",
            "~": "`"
        ]
        
        let lowercased = Character(char.lowercased())
        
        // Check direct mapping first
        if let keyCode = charToKeyCode[lowercased] {
            return keyCode
        }
        
        // Check if it's a shifted character
        if let baseChar = shiftCharToBaseChar[char],
           let keyCode = charToKeyCode[baseChar] {
            return keyCode
        }
        
        return nil
    }
    
    private func shiftRequired(_ char: Character) -> Bool {
        let shiftChars = "~!@#$%^&*()_+{}|:\"<>?ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return shiftChars.contains(char)
    }
}

// MARK: - Browser Click Tool

/// Click at specific coordinates
class BrowserClickTool: BaseAgentTool {
    init() {
        super.init(
            name: "browser_click",
            description: "Click at screen coordinates",
            parameterSchema: [
                "x": "X coordinate on screen",
                "y": "Y coordinate on screen"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let x = Double(try requireParam("x", from: params)) ?? 0
        let y = Double(try requireParam("y", from: params)) ?? 0
        
        let point = CGPoint(x: x, y: y)
        
        print("🖱️ Clicking at (\(x), \(y))")
        
        // Move mouse
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)
        
        // Wait a moment
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Click
        let clickDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        clickDown?.post(tap: .cghidEventTap)
        
        let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        clickUp?.post(tap: .cghidEventTap)
        
        return "Clicked at (\(Int(x)), \(Int(y)))"
    }
}

// MARK: - Browser Scroll Tool

/// Scroll the page up or down
class BrowserScrollTool: BaseAgentTool {
    init() {
        super.init(
            name: "browser_scroll",
            description: "Scroll the browser page",
            parameterSchema: [
                "direction": "up or down",
                "amount": "Optional scroll amount (default: 300)"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let direction = try requireParam("direction", from: params)
        let amount = Int(params["amount"] ?? "300") ?? 300
        
        let scrollAmount = direction.lowercased() == "up" ? amount : -amount
        
        print("📜 Scrolling \(direction) by \(amount)")
        
        // Smooth scroll in increments
        let steps = 10
        let stepAmount = scrollAmount / steps
        
        for _ in 0..<steps {
            let scrollEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(stepAmount), wheel2: 0, wheel3: 0)
            scrollEvent?.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms between steps
        }
        
        return "Scrolled \(direction)"
    }
}

// MARK: - Browser Focus Search Tool

/// Focus the browser's address bar or search box
class BrowserFocusSearchTool: BaseAgentTool {
    init() {
        super.init(
            name: "browser_focus_search",
            description: "Focus the frontmost browser's address bar (Cmd+L) and optionally clear it",
            parameterSchema: [
                "clear": "Optional: 'true' to clear existing content (default: true)"
            ]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        let shouldClear = (params["clear"] ?? "true").lowercased() == "true"
        
        print("🔍 Focusing browser search bar")
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Cmd+L to focus address bar (works in Chrome, Safari, Firefox, Edge)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true) // Cmd key
        cmdDown?.post(tap: .cghidEventTap)
        
        let lDown = CGEvent(keyboardEventSource: source, virtualKey: 37, keyDown: true) // L key
        lDown?.flags = .maskCommand
        lDown?.post(tap: .cghidEventTap)
        
        let lUp = CGEvent(keyboardEventSource: source, virtualKey: 37, keyDown: false)
        lUp?.flags = .maskCommand
        lUp?.post(tap: .cghidEventTap)
        
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Clear existing content if requested
        if shouldClear {
            // Cmd+A to select all
            let cmdADown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true)
            cmdADown?.post(tap: .cghidEventTap)
            
            let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            aDown?.flags = .maskCommand
            aDown?.post(tap: .cghidEventTap)
            
            let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            aUp?.flags = .maskCommand
            aUp?.post(tap: .cghidEventTap)
            
            let cmdAUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false)
            cmdAUp?.post(tap: .cghidEventTap)
            
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        
        return "Focused browser search bar"
    }
}

// MARK: - Browser Press Enter Tool

/// Press Enter/Return key
class BrowserPressEnterTool: BaseAgentTool {
    init() {
        super.init(
            name: "browser_press_enter",
            description: "Press the Enter/Return key",
            parameterSchema: [:]
        )
    }
    
    override func execute(params: [String: String]) async throws -> String {
        print("⏎ Pressing Enter")
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        let enterDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        enterDown?.post(tap: .cghidEventTap)
        
        let enterUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        enterUp?.post(tap: .cghidEventTap)
        
        // Wait for action to complete
        try await Task.sleep(nanoseconds: 500_000_000)
        
        return "Pressed Enter"
    }
}

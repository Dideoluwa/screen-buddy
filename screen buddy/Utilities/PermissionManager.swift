//
//  PermissionManager.swift
//  screen buddy
//
//  Centralized permission handling for Accessibility and other system permissions
//

import Foundation
import AppKit
import AVFoundation
import Speech

/// Manages system permissions required by the app
@Observable @MainActor
class PermissionManager {
    
    // MARK: - Permission States
    
    var accessibilityGranted: Bool = false
    var screenRecordingGranted: Bool = false
    var microphoneGranted: Bool = false
    var speechRecognitionGranted: Bool = false
    
    // MARK: - Singleton
    
    static let shared = PermissionManager()
    
    private init() {
        checkAllPermissions()
    }
    
    // MARK: - Check Permissions
    
    func checkAllPermissions() {
        checkAccessibility()
        checkScreenRecording()
        checkMicrophone()
        checkSpeechRecognition()
    }
    
    /// Check if Accessibility permission is granted
    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }
    
    /// Check if Screen Recording permission is granted
    func checkScreenRecording() {
        screenRecordingGranted = ScreenCaptureService.shared.hasPermissionSync
    }
    
    /// Check if Microphone permission is granted
    func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
    }
    
    /// Check if Speech Recognition permission is granted
    func checkSpeechRecognition() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionGranted = true
        default:
            speechRecognitionGranted = false
        }
    }
    
    // MARK: - Request Permissions
    
    /// Request Accessibility permission - opens System Settings
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        accessibilityGranted = trusted
        
        if !trusted {
            // Open System Settings to Accessibility
            openAccessibilitySettings()
        }
    }
    
    /// Request Microphone permission
    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneGranted = granted
        }
    }
    
    /// Request Speech Recognition permission
    func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.speechRecognitionGranted = status == .authorized
            }
        }
    }
    
    // MARK: - Open Settings
    
    /// Open Accessibility settings in System Settings
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open Microphone settings in System Settings
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open Speech Recognition settings in System Settings
    func openSpeechRecognitionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Permission Status
    
    /// Returns true if all essential permissions are granted
    var allEssentialPermissionsGranted: Bool {
        return accessibilityGranted
    }
    
    /// Returns a list of missing permissions
    var missingPermissions: [String] {
        var missing: [String] = []
        if !accessibilityGranted { missing.append("Accessibility") }
        if !microphoneGranted { missing.append("Microphone") }
        if !speechRecognitionGranted { missing.append("Speech Recognition") }
        return missing
    }
}

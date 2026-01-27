//
//  ScreenCaptureService.swift
//  screen buddy
//
//  Captures screenshots for visual context using ScreenCaptureKit
//

import Foundation
import AppKit
import ScreenCaptureKit

/// Service for capturing screenshots of the screen
@MainActor
class ScreenCaptureService: NSObject {
    
    // MARK: - Singleton
    
    static let shared = ScreenCaptureService()
    
    // Track if we've verified permission
    private var permissionVerified: Bool = false
    
    private override init() {
        super.init()
    }
    
    // MARK: - Permission
    
    /// Synchronous permission check - uses cached value or assumes true
    /// Actual check happens on first capture attempt
    nonisolated var hasPermissionSync: Bool {
        // We can't do a proper sync check with ScreenCaptureKit
        // Return true and let the capture fail gracefully if permission isn't granted
        return true
    }
    
    /// Request screen recording permission by attempting to access content
    func requestPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            permissionVerified = true
            return true
        } catch {
            print("⚠️ Screen capture permission not granted: \(error.localizedDescription)")
            // Open System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return false
        }
    }
    
    // MARK: - Capture
    
    /// Capture the main display and return as base64 JPEG
    func captureAsBase64(maxSize: CGFloat = 1024) async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = content.displays.first else {
                print("⚠️ No display found")
                return nil
            }
            
            // Calculate scaled size maintaining aspect ratio
            let aspectRatio = CGFloat(display.width) / CGFloat(display.height)
            var width = min(CGFloat(display.width), maxSize)
            var height = width / aspectRatio
            
            if height > maxSize {
                height = maxSize
                width = height * aspectRatio
            }
            
            // Configure capture
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(width)
            configuration.height = Int(height)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = false
            
            // Capture single frame
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            
            // Convert CGImage to JPEG data
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else {
                print("⚠️ Failed to convert screenshot to JPEG")
                return nil
            }
            
            permissionVerified = true
            print("📸 Screenshot captured: \(jpegData.count / 1024)KB (\(Int(width))x\(Int(height)))")
            return jpegData.base64EncodedString()
            
        } catch {
            print("❌ Screen capture failed: \(error.localizedDescription)")
            // ... (error handling)
            return nil
        }
    }
    
    /// Capture main display as CGImage (for local processing/diffing)
    /// Returns raw image without JPEG compression overhead
    func captureAsCGImage(maxSize: CGFloat = 1024) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = content.displays.first else { return nil }
            
            // Calculate size
            let aspectRatio = CGFloat(display.width) / CGFloat(display.height)
            var width = min(CGFloat(display.width), maxSize)
            var height = width / aspectRatio
            
            if height > maxSize {
                height = maxSize
                width = height * aspectRatio
            }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(width)
            configuration.height = Int(height)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = false
            
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            
            permissionVerified = true
            return image
        } catch {
            print("❌ Resize capture failed: \(error)")
            return nil
        }
    }
}

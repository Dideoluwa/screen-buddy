import Foundation
import AppKit
import Vision

/// Handles "Intelligent Visual Sampling"
/// Triggers only when:
/// 1. Video intent is detected
/// 2. Audio is low confidence/silent
/// 3. Visual content changes significantly
class VisualSampler: ObservableObject {
    
    // MARK: - Configuration
    private let sampleInterval: TimeInterval = 3.0
    private let diffThreshold: Float = 0.10 // 10% change triggers event
    
    // MARK: - State
    @Published var lastVisualEvent: String = ""
    private var lastImage: CGImage?
    private var isRunning: Bool = false
    private var timer: Timer?
    
    // Dependencies
    // We access ContextEngine state via dependency injection or observer
    // For now, we will expose methods called by ContextEngine
    
    // MARK: - Public API
    
    func startSampling() {
        guard !isRunning else { return }
        isRunning = true
        print("👁️ VisualSampler: Started Loop")
        
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performCheck()
            }
        }
    }
    
    func stopSampling() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        lastImage = nil
    }
    
    // MARK: - Logic
    
    private func performCheck() async {
        // 1. Capture Frame (Low Res for Diff)
        // We use 512px for diffing to be fast
        guard let currentImage = await ScreenCaptureService.shared.captureAsCGImage(maxSize: 512) else { return }
        
        // 2. Diff
        if let last = lastImage {
            let diff = calculateDiff(imageA: last, imageB: currentImage)
            if diff < diffThreshold {
                // No significant change
                return
            }
        }
        
        // Significant change detected or first frame
        lastImage = currentImage
        
        // 3. Analyze with Gemini
        // We re-capture at higher res or use the current 512 if sufficient? 
        // 512 is usually enough for shape detection. Let's use the current one.
        // Convert to Base64
        guard let jpegData = convertToJPEG(currentImage) else { return }
        let base64 = jpegData.base64EncodedString()
        
        print("👁️ Visual Event Detected (Diff: 10%+). Analyzing...")
        
        do {
            let prompt = "Describe significant visual changes or diagrams on screen. Be extremely concise. Focus on shapes, code, or playback state."
            let response = try await GeminiService.shared.chat(
                message: prompt,
                context: nil,
                includeScreenshot: false, // We provide custom image
                customImageBase64: base64
            )
            
            DispatchQueue.main.async {
                self.lastVisualEvent = "[\(Date().formatted(date: .omitted, time: .standard))] Visual: \(response)"
            }
        } catch {
            print("❌ Visual Analysis Failed: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func calculateDiff(imageA: CGImage, imageB: CGImage) -> Float {
        // FeaturePrint observation is robust but slow.
        // Simple byte comparison is brittle.
        // Let's use VNGenerateImageFeaturePrintRequest for robustness (Scene Change Detection).
        
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        
        let handlerA = VNImageRequestHandler(cgImage: imageA, options: [:])
        let handlerB = VNImageRequestHandler(cgImage: imageB, options: [:])
        
        do {
            try handlerA.perform([request])
            guard let resultA = request.results?.first as? VNFeaturePrintObservation else { return 0 }
            
            try handlerB.perform([request])
            guard let resultB = request.results?.first as? VNFeaturePrintObservation else { return 0 }
            
            var distance: Float = 0
            try resultA.computeDistance(&distance, to: resultB)
            
            return distance // 0.0 = identical, 1.0 = different
        } catch {
            print("Diff Error: \(error)")
            return 0
        }
    }
    
    private func convertToJPEG(_ cgImage: CGImage) -> Data? {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }
}

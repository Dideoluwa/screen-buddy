import Foundation
import ScreenCaptureKit
import Speech
import AVFoundation

/// Monitors system audio and transcribes it in real-time.
/// Uses ScreenCaptureKit for capture and SFSpeechRecognizer for on-device transcription.
///
/// IMPORTANT: This class is designed to be OPT-IN. Call `startMonitoring()` explicitly
/// only when audio context is needed. It is NOT started automatically to avoid
/// blocking the main thread during app launch.
class AudioContextMonitor: NSObject, SCStreamOutput, SFSpeechRecognizerDelegate, ObservableObject {
    
    // MARK: - Published State
    @Published var currentTranscript: String = ""
    @Published var isListening: Bool = false
    @Published var isAvailable: Bool = false
    
    // MARK: - Private Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var stream: SCStream?
    private let audioQueue = DispatchQueue(label: "com.screenbuddy.audio", qos: .userInitiated)
    
    // Permission state
    private var hasPermission: Bool = false
    
    override init() {
        super.init()
        // DON'T check permissions in init - do it lazily
    }
    
    // MARK: - Permission Check (Call before starting)
    
    func checkPermissions() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let authorized = (status == .authorized)
                DispatchQueue.main.async {
                    self.hasPermission = authorized
                    self.isAvailable = authorized
                }
                if authorized {
                    print("🎤 Speech Recognition authorized")
                } else {
                    print("❌ Speech Recognition denied")
                }
                continuation.resume(returning: authorized)
            }
        }
    }
    
    // MARK: - Public API
    
    /// Start audio monitoring. This is a heavy operation and should only be called
    /// when audio context is actually needed.
    func startMonitoring() async {
        // Ensure we don't double-start
        guard !isListening else { return }
        
        // Check permissions first
        guard await checkPermissions() else {
            print("❌ Audio: No permission")
            return
        }
        
        // Initialize speech recognizer lazily
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            speechRecognizer?.delegate = self
        }
        
        do {
            // 1. Get Shareable Content
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let mainDisplay = content.displays.first else {
                print("❌ No display found for audio capture")
                return
            }
            
            // 2. Filter
            let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: mainDisplay, excludingApplications: excludedApps, exceptingWindows: [])
            
            // 3. Config - Audio only, minimal video
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 16000 // 16kHz is sufficient for speech
            config.channelCount = 1
            
            // Disable video completely
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 10, timescale: 1) // 0.1 FPS
            config.showsCursor = false
            
            // 4. Create Stream
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            // 5. Add Output on background queue
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            
            // 6. Start (this is the potentially slow part)
            try await stream?.startCapture()
            
            // 7. Start Speech Recognition
            startRecognitionSession()
            
            await MainActor.run {
                self.isListening = true
            }
            print("👂 Audio System: Started Listening")
            
        } catch {
            print("❌ Audio Capture Failed: \(error.localizedDescription)")
        }
    }
    
    func stopMonitoring() {
        audioQueue.async { [weak self] in
            self?.stream?.stopCapture()
            self?.recognitionTask?.cancel()
            self?.stream = nil
            self?.recognitionRequest = nil
            self?.recognitionTask = nil
            
            DispatchQueue.main.async {
                self?.isListening = false
            }
        }
    }
    
    // MARK: - Speech Recognition
    
    private func startRecognitionSession() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        
        recognitionRequest = request
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self?.currentTranscript = result.bestTranscription.formattedString
                }
            }
            
            if let error = error {
                print("⚠️ Speech Recognition Error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - SCStreamOutput
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let request = recognitionRequest else { return }
        request.appendAudioSampleBuffer(sampleBuffer)
    }
}

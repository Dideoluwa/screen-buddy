import Foundation
import ScreenCaptureKit
import Speech
import Cocoa
import Combine

/// The brain of the Context Fusion system.
/// Orchestrates signals from Audio, Metadata, and Interaction monitors.
class ContextEngine: ObservableObject {
    
    static let shared = ContextEngine()
    
    // MARK: - Published State
    @Published var activeApp: String = "Unknown"
    @Published var windowTitle: String = "Unknown"
    @Published var lastTranscript: String = ""
    @Published var interactionState: String = "Idle"
    
    // MARK: - Sub-Systems
     private let audioMonitor = AudioContextMonitor()
     private let metadataMonitor = MetadataMonitor()
     private let interactionMonitor = InteractionMonitor()
     private let visionSampler = VisualSampler()
    
    // MARK: - Context Buffers
    private var immediateContextBuffer: [String] = [] // Last ~2 mins
    private var summaryBuffer: String = "" // Last ~30 mins
    private var isMonitoring: Bool = false
    
    init() {
        print("🧠 ContextEngine: Ready (not started - enable via Context Awareness toggle)")
        // DON'T auto-start - wait for user to enable via menu
    }
    
    private func startMonitoring() {
        guard !isMonitoring else {
            print("🧠 ContextEngine: Already running, skipping double-start")
            return
        }
        isMonitoring = true
        print("🧠 ContextEngine: Starting Sub-Monitors...")
        
        // Metadata (Lightweight - start immediately)
        metadataMonitor.startMonitoring()
        
        // Interaction (Lightweight - start immediately)
        interactionMonitor.startMonitoring()
        
        // Audio (Heavy - start with delay to not block UI)
        // This gives the UI 2 seconds to become responsive first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            Task {
                await self?.audioMonitor.startMonitoring()
            }
        }
        
        // Bind Outputs to Engine State
        
        // Audio
        audioMonitor.$currentTranscript
            .assign(to: &$lastTranscript)
            
        // Metadata
        metadataMonitor.$activeApp
            .assign(to: &$activeApp)
        
        metadataMonitor.$windowTitle
            .assign(to: &$windowTitle)
            
        // Interaction
        interactionMonitor.$interactionState
            .sink { [weak self] state in
                self?.interactionState = state
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
            
        // Vision
        visionSampler.$lastVisualEvent
            .sink { [weak self] event in
                guard !event.isEmpty else { return }
                self?.appendToContext(event)
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private func handleStateChange(_ state: String) {
        // Intelligent Trigger: Sample visuals when user is likely watching content
        
        // Check if user is in a media/video context based on app or window
        let isMediaApp = checkIfMediaApp()
        let isVideoContent = checkIfVideoContent()
        
        // User is "Watching" if:
        // 1. They're idle/reading (not actively interacting) AND
        // 2. They're in a media app OR video content is detected
        let isWatching = (state == "Idle" || state == "Reading") && (isMediaApp || isVideoContent)
        
        if isWatching || state == "Reading" {
            visionSampler.startSampling()
            if isWatching {
                print("👁️ VisualSampler: Triggered (Watching detected - \(activeApp))")
            }
        } else {
            visionSampler.stopSampling()
        }
    }
    
    /// Check if current app is a media/video player
    private func checkIfMediaApp() -> Bool {
        let bundleId = metadataMonitor.activeBundleId?.lowercased() ?? ""
        
        let mediaAppIdentifiers = [
            "youtube", "netflix", "primevideo", "hulu", "disney", "hbomax",
            "vlc", "iina", "quicktime", "tv.apple", "spotify",
            "zoom", "webex", "teams", "meet" // Video calls
        ]
        
        return mediaAppIdentifiers.contains { bundleId.contains($0) }
    }
    
    /// Check if window title suggests video content
    private func checkIfVideoContent() -> Bool {
        let title = windowTitle.lowercased()
        
        let videoIndicators = [
            "youtube", "netflix", "video", "watch", "movie", "episode",
            "streaming", "playing", "tutorial", "course", "lesson"
        ]
        
        return videoIndicators.contains { title.contains($0) }
    }
    
    private func appendToContext(_ event: String) {
        immediateContextBuffer.append(event)
        // Basic pruning
        if immediateContextBuffer.count > 20 {
            immediateContextBuffer.removeFirst()
        }
    }
    
    // MARK: - Legacy Compatibility (for NudgeManager & AppDelegate)
    
    /// Timestamp of last user activity (from InteractionMonitor)
    var lastActivityTimestamp: Date {
        // Since we don't expose raw timestamps from InteractionMonitor yet,
        // we'll return Date() if active, or a past date if idle.
        // For accurate idle detection, NudgeManager uses this.
        // Let's approximate:
        if interactionState == "Idle" {
            return Date().addingTimeInterval(-600) // 10 mins ago
        } else {
            return Date()
        }
    }
    
    /// Current System Context Snapshot
    var currentContext: SystemContext {
        let appName = activeApp
        let bundleId = metadataMonitor.activeBundleId
        let title = windowTitle
        
        // Determine Category
        let category = AppCategory.from(bundleId: bundleId)
        
        let appInfo = AppInfo(
            name: appName,
            bundleIdentifier: bundleId,
            category: category,
            isActive: true
        )
        
        let fileType = FileType.from(windowTitle: title)
        
        // Construct SystemContext
        return SystemContext(
            activeApp: appInfo,
            windowTitle: title,
            selectedText: nil, // Not implemented in privacy-first mode
            cursorPosition: .zero, // Not tracked
            hoveredElement: nil, // Not tracked
            fileType: fileType,
            browserURL: nil, // Not tracked
            timestamp: Date()
        )
    }
    
    func start() {
        startMonitoring()
    }
    
    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        print("🧠 ContextEngine: Stopping...")
        
        audioMonitor.stopMonitoring()
        metadataMonitor.stopMonitoring()
        interactionMonitor.stopMonitoring()
        visionSampler.stopSampling()
    }
    
    func forceRefresh() -> SystemContext {
        // In our reactive system, currentContext is always fresh-ish.
        return currentContext
    }
    
    /// Returns the constructed prompt context for the LLM with detailed source logging
    func getContextSnapshot() -> String {
        var contextParts: [String] = []
        var logParts: [String] = []
        
        // 1. Metadata (App/Window)
        if activeApp != "Unknown" {
            contextParts.append("[Metadata - App] \(activeApp)")
            logParts.append("📱 Metadata: App=\(activeApp)")
        }
        if windowTitle != "Unknown" && !windowTitle.isEmpty {
            contextParts.append("[Metadata - Window] \(windowTitle)")
            logParts.append("🪟 Metadata: Window=\(windowTitle)")
        }
        
        // 2. Interaction State
        if interactionState != "Idle" {
            contextParts.append("[Interaction] User is \(interactionState)")
            logParts.append("🖱️ Interaction: State=\(interactionState)")
        }
        
        // 3. Audio Transcript
        if !lastTranscript.isEmpty {
            // Truncate if too long
            let truncated = lastTranscript.count > 500 
                ? String(lastTranscript.prefix(500)) + "..." 
                : lastTranscript
            contextParts.append("[Audio Transcript] \(truncated)")
            logParts.append("🎧 Audio: \(truncated.prefix(100))...")
        }
        
        // 4. Visual Events (from buffer)
        if !immediateContextBuffer.isEmpty {
            let visualEvents = immediateContextBuffer.joined(separator: "\n")
            contextParts.append("[Visual Events]\n\(visualEvents)")
            logParts.append("👁️ Visual: \(immediateContextBuffer.count) events")
        }
        
        // 5. Summary Buffer (long-term context)
        if !summaryBuffer.isEmpty {
            contextParts.append("[Session Summary] \(summaryBuffer)")
            logParts.append("📝 Summary: Available")
        }
        
        // Log what context is being sent
        if !logParts.isEmpty {
            print("🧠 ───────────────────────────────────")
            print("🧠 CONTEXT BEING SENT TO GEMINI:")
            for part in logParts {
                print("   \(part)")
            }
            print("🧠 ───────────────────────────────────")
        } else {
            print("🧠 No context available (Context Awareness may be disabled)")
        }
        
        return contextParts.joined(separator: "\n")
    }
}

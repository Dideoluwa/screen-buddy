//
//  RobotView.swift
//  screen buddy
//
//  Main SwiftUI view for the robot character with all interactions
//

import SwiftUI

/// Main robot view with gesture handling and state management
struct RobotView: View {
    @EnvironmentObject var panelController: FloatingPanelController
    @State private var eyeOpenAmount: CGFloat = 1.0
    @State private var isDragging: Bool = false
    @State private var dragStartMouseLocation: NSPoint = .zero
    @State private var dragStartPanelOrigin: CGPoint = .zero
    @State private var showMenu: Bool = false
    
    let size: CGFloat = 48
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Robot character
            RobotCharacter(
                expression: panelController.robotState.expression,
                lookDirection: panelController.robotState.lookDirection,
                eyeOpenAmount: eyeOpenAmount,
                size: size
            )
            .breathing()
            .blinking(eyeOpenAmount: $eyeOpenAmount)
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        if !isDragging {
                            handleTap()
                        }
                    }
            )
            .highPriorityGesture(dragGesture)
            .padding(.bottom, 20) // Keep robot slightly off the bottom edge
            .contextMenu {
                Toggle("Show Chat History", isOn: Binding(
                    get: { panelController.robotState.showHistory },
                    set: { newValue in
                        panelController.robotState.showHistory = newValue
                        ChatHistoryManager.shared.saveShowHistoryPreference(newValue)
                    }
                ))
                
                Toggle("Context Awareness", isOn: Binding(
                    get: { panelController.robotState.isContextAwarenessEnabled },
                    set: { newValue in
                        panelController.robotState.isContextAwarenessEnabled = newValue
                        if newValue {
                            // Start context engine in background
                            Task {
                                ContextEngine.shared.start()
                            }
                        } else {
                            ContextEngine.shared.stop()
                        }
                    }
                ))
                
                Divider()
                Button("Settings...") {
                    // TODO: Open settings
                }
                Divider()
                Button("Hide Robot") {
                    panelController.hidePanel()
                }
                Button("Quit Screen Buddy") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .zIndex(1) // Ensure robot is always interactive
            
            // Chat bubble (above robot)
            if panelController.robotState.showResponseBubble {
                ChatBubble(
                    robotState: panelController.robotState,
                    onClose: {
                        InteractionManager.shared.closeChat(robotState: panelController.robotState)
                    }
                )
                .offset(y: -size - 50) // Adjust offset for bottom alignment
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
                .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
    
    // MARK: - Gestures
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                // Get current mouse location in screen coordinates
                let currentMouseLocation = NSEvent.mouseLocation
                
                if !isDragging {
                    isDragging = true
                    panelController.isDragging = true
                }
                
                // Get panel size to center robot on cursor
                let panelSize = panelController.panelFrame?.size ?? CGSize(width: 140, height: 140)
                
                // Position panel so robot (at bottom center) is at cursor
                // Robot is centered horizontally and near bottom of panel
                let newX = currentMouseLocation.x - (panelSize.width / 2)
                let newY = currentMouseLocation.y - 50 // Offset to put cursor on robot body
                
                panelController.updatePosition(CGPoint(x: newX, y: newY))
            }
            .onEnded { _ in
                isDragging = false
                panelController.isDragging = false
                panelController.snapToEdge()
            }
    }
    
    // MARK: - Actions
    
    private func handleTap() {
        // Toggle chat bubble
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if panelController.robotState.showResponseBubble {
                 // If already open, do nothing or pulse? 
                 // Or we can close it if user wants to toggle off?
                 // Let's toggle it off to be consistent with standard behaviour
                 panelController.robotState.showResponseBubble = false
            } else {
                panelController.robotState.showResponseBubble = true
                panelController.robotState.expression = .curious
            }
        }
        
        // Reset expression after a bit if just opened
        if panelController.robotState.showResponseBubble {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                panelController.robotState.expression = .idle
            }
        }
    }
    
    private func handleInput(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Use InteractionManager for async processing
        Task {
            await InteractionManager.shared.handleUserInput(text, robotState: panelController.robotState)
        }
    }
}

// MARK: - Input Bubble

struct InputBubble: View {
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask me anything...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .focused($isFocused)
                .onSubmit {
                    submitInput()
                }
            
            Button(action: submitInput) {
                ZStack {
                    if inputText.isEmpty {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                    }
                    
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(inputText.isEmpty ? .gray : .white)
                }
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                // Dark glass base for better readability
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.black.opacity(0.6))
                
                // Glassy material overlay
                RoundedRectangle(cornerRadius: 22)
                    .fill(.thickMaterial)
                    .opacity(0.8)
                
                // Border glow
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hex: "667EEA").opacity(0.5),
                                Color(hex: "764BA2").opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
        )
        .frame(width: 260)
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            onDismiss()
        }
    }
    
    private func submitInput() {
        guard !inputText.isEmpty else { return }
        onSubmit(inputText)
        inputText = ""
    }
}

// MARK: - Response Bubble

// MARK: - Chat Bubble

struct ChatBubble: View {
    var robotState: RobotState
    let onClose: () -> Void
    
    @State private var inputText: String = ""
    @FocusState private var isFocused: Bool
    
    private let maxHeight: CGFloat = 350
    private let compactHeight: CGFloat = 180 // Height when history is hidden (input + latest message)
    
    /// Messages excluding the latest one (older history)
    private var olderMessages: [ChatMessage] {
        guard robotState.chatHistory.count > 1 else { return [] }
        return Array(robotState.chatHistory.dropLast())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if robotState.isAgentMode {
                    // Agent Mode Header
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("Agent Mode")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.yellow)
                    }
                } else {
                    Text("Chat with Buddy")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Show/Hide History Toggle Button (hide during agent mode)
                if !robotState.isAgentMode {
                    Button(action: {
                        robotState.showHistory.toggle()
                        ChatHistoryManager.shared.saveShowHistoryPreference(robotState.showHistory)
                    }) {
                        Image(systemName: robotState.showHistory ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(robotState.showHistory ? "Hide History" : "Show History")
                }
                
                // Clear History Button
                Button(action: {
                    InteractionManager.shared.clearHistory(robotState: robotState)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Clear History")
                
                // Close Button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(robotState.isAgentMode ? Color(hex: "3B2F4F").opacity(0.8) : Color.black.opacity(0.2))
            
            // Agent Progress Section
            if robotState.isAgentMode {
                VStack(alignment: .leading, spacing: 8) {
                    // Progress bar
                    if robotState.totalAgentSteps > 0 {
                        HStack(spacing: 8) {
                            Text("Step \(robotState.currentAgentStep)/\(robotState.totalAgentSteps)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                            
                            ProgressView(value: Double(robotState.currentAgentStep), 
                                       total: Double(robotState.totalAgentSteps))
                                .progressViewStyle(LinearProgressViewStyle(tint: Color(hex: "667EEA")))
                                .frame(height: 4)
                        }
                    }
                    
                    // Current action
                    if !robotState.agentProgress.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            
                            Text(robotState.agentProgress)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(2)
                        }
                    }
                    
                    // Agent question with Yes/No buttons
                    if AgentLoopController.shared.state.isWaitingForUser {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AgentLoopController.shared.pendingQuestion)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(3)
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    AgentLoopController.shared.provideUserResponse("yes")
                                }) {
                                    Text("Yes")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(Color(hex: "667EEA"))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: {
                                    AgentLoopController.shared.provideUserResponse("no")
                                }) {
                                    Text("No")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(hex: "2D2440").opacity(0.6))
            }
            
            // Content area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Older history - only shown when showHistory is true
                        if robotState.showHistory {
                            ForEach(olderMessages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        
                        // Latest message - ALWAYS shown
                        if let latestMessage = robotState.chatHistory.last {
                            MessageBubbleView(message: latestMessage)
                                .id(latestMessage.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: robotState.chatHistory) {
                    if let lastId = robotState.chatHistory.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Input Field
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .onSubmit {
                        submitInput()
                    }
                
                Button(action: submitInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(inputText.isEmpty ? .gray : Color(hex: "667EEA"))
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
            .padding(10)
            .background(Color.black.opacity(0.3))
        }
        .frame(width: 320)
        .frame(height: robotState.showHistory ? maxHeight : compactHeight)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: robotState.showHistory)
        .background(
            ZStack {
                // Very subtle dark base for contrast
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.25))
                
                // Ultra thin material for glass effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
                
                // Border glow
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.15),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            isFocused = true
        }
    }
    
    private func submitInput() {
        guard !inputText.isEmpty else { return }
        
        let text = inputText
        inputText = ""
        
        Task {
            // Keep window open while thinking, handleUserInput will update status
            await InteractionManager.shared.handleUserInput(text, robotState: robotState)
        }
    }
}

// MARK: - Message Bubble View

/// Reusable view for rendering a single chat message
struct MessageBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer()
                Text(message.text)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "667EEA"), Color(hex: "764BA2")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12, corners: [.topLeft, .topRight, .bottomLeft])
            } else {
                Text(message.text)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12, corners: [.topLeft, .topRight, .bottomRight])
                    .textSelection(.enabled)
                Spacer()
            }
        }
    }
}

// Helper for custom corner radius
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let p1 = CGPoint(x: rect.minX, y: rect.minY)
        let p2 = CGPoint(x: rect.maxX, y: rect.minY)
        let p3 = CGPoint(x: rect.maxX, y: rect.maxY)
        let p4 = CGPoint(x: rect.minX, y: rect.maxY)

        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomRight = corners.contains(.bottomRight)
        let bottomLeft = corners.contains(.bottomLeft)

        path.move(to: CGPoint(x: p1.x + (topLeft ? radius : 0), y: p1.y))

        path.addLine(to: CGPoint(x: p2.x - (topRight ? radius : 0), y: p2.y))
        if topRight {
            path.addArc(center: CGPoint(x: p2.x - radius, y: p2.y + radius), radius: radius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        }

        path.addLine(to: CGPoint(x: p3.x, y: p3.y - (bottomRight ? radius : 0)))
        if bottomRight {
            path.addArc(center: CGPoint(x: p3.x - radius, y: p3.y - radius), radius: radius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        }

        path.addLine(to: CGPoint(x: p4.x + (bottomLeft ? radius : 0), y: p4.y))
        if bottomLeft {
            path.addArc(center: CGPoint(x: p4.x + radius, y: p4.y - radius), radius: radius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        }

        path.addLine(to: CGPoint(x: p1.x, y: p1.y + (topLeft ? radius : 0)))
        if topLeft {
            path.addArc(center: CGPoint(x: p1.x + radius, y: p1.y + radius), radius: radius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        }

        path.closeSubpath()
        return path
    }
}

/// Speech bubble shape with pointer
struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 12
        let pointerSize: CGFloat = 8
        
        // Main rounded rectangle
        path.addRoundedRect(
            in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height - pointerSize),
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        
        // Pointer at bottom center
        let pointerX = rect.midX
        path.move(to: CGPoint(x: pointerX - pointerSize, y: rect.height - pointerSize))
        path.addLine(to: CGPoint(x: pointerX, y: rect.height))
        path.addLine(to: CGPoint(x: pointerX + pointerSize, y: rect.height - pointerSize))
        
        return path
    }
}

#Preview {
    RobotView()
        .environmentObject(FloatingPanelController())
        .frame(width: 300, height: 300)
        .background(Color.gray.opacity(0.2))
}

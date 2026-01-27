//
//  RobotAnimations.swift
//  screen buddy
//
//  Animation definitions for the robot character
//

import SwiftUI

/// Animation presets for robot behaviors
struct RobotAnimations {
    
    // MARK: - Breathing Animation
    
    static let breathingAnimation = Animation
        .easeInOut(duration: 2.5)
        .repeatForever(autoreverses: true)
    
    static let breathingScale: (min: CGFloat, max: CGFloat) = (0.97, 1.03)
    
    // MARK: - Blinking Animation
    
    static let blinkDuration: Double = 0.15
    static let blinkInterval: ClosedRange<Double> = 2.0...5.0
    
    // MARK: - Bounce Animation
    
    static let bounceAnimation = Animation
        .interpolatingSpring(stiffness: 300, damping: 10)
    
    // MARK: - Talking Animation
    
    static let talkingAnimation = Animation
        .easeInOut(duration: 0.1)
        .repeatForever(autoreverses: true)
    
    // MARK: - Look Animation
    
    static let lookAnimation = Animation
        .easeOut(duration: 0.3)
    
    // MARK: - Reaction Animations
    
    static let happyBounce = Animation
        .interpolatingSpring(stiffness: 400, damping: 8)
    
    static let curiousTilt = Animation
        .easeInOut(duration: 0.4)
    
    static let surprisedJump = Animation
        .interpolatingSpring(stiffness: 500, damping: 12)
}

/// View modifier for breathing animation
struct BreathingModifier: ViewModifier {
    @State private var isBreathing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isBreathing ? RobotAnimations.breathingScale.max : RobotAnimations.breathingScale.min)
            .onAppear {
                withAnimation(RobotAnimations.breathingAnimation) {
                    isBreathing = true
                }
            }
    }
}

/// View modifier for blinking
struct BlinkingModifier: ViewModifier {
    @Binding var eyeOpenAmount: CGFloat
    @State private var blinkTimer: Timer?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                startBlinking()
            }
            .onDisappear {
                blinkTimer?.invalidate()
            }
    }
    
    private func startBlinking() {
        scheduleNextBlink()
    }
    
    private func scheduleNextBlink() {
        let interval = Double.random(in: RobotAnimations.blinkInterval)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            blink()
        }
    }
    
    private func blink() {
        withAnimation(.easeOut(duration: RobotAnimations.blinkDuration)) {
            eyeOpenAmount = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + RobotAnimations.blinkDuration) {
            withAnimation(.easeIn(duration: RobotAnimations.blinkDuration)) {
                eyeOpenAmount = 1
            }
            scheduleNextBlink()
        }
    }
}

extension View {
    func breathing() -> some View {
        modifier(BreathingModifier())
    }
    
    func blinking(eyeOpenAmount: Binding<CGFloat>) -> some View {
        modifier(BlinkingModifier(eyeOpenAmount: eyeOpenAmount))
    }
}

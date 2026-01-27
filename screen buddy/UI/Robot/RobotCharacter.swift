//
//  RobotCharacter.swift
//  screen buddy
//
//  Visual components of the robot character - Modern, intelligent design
//

import SwiftUI

/// The robot's eye component - sleek and expressive
struct RobotEye: View {
    let size: CGFloat
    let lookDirection: CGPoint
    let openAmount: CGFloat
    let isLeft: Bool
    
    private var pupilOffset: CGPoint {
        let maxOffset = size * 0.15
        return CGPoint(
            x: lookDirection.x * maxOffset,
            y: -lookDirection.y * maxOffset
        )
    }
    
    var body: some View {
        ZStack {
            // Glowing eye socket
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "E8F4FD"),
                            Color.white
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 1.1, height: size * openAmount * 0.9)
                .shadow(color: Color(hex: "00D9FF").opacity(0.3), radius: 4, x: 0, y: 0)
            
            // Pupil - smart looking
            if openAmount > 0.3 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "1A1A2E"),
                                Color(hex: "0F0F1A")
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.2
                        )
                    )
                    .frame(width: size * 0.4, height: size * 0.4)
                    .offset(x: pupilOffset.x, y: pupilOffset.y)
                    .overlay(
                        // Bright highlight for intelligence look
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.white, Color.white.opacity(0)],
                                    center: UnitPoint(x: 0.3, y: 0.3),
                                    startRadius: 0,
                                    endRadius: size * 0.15
                                )
                            )
                            .frame(width: size * 0.2, height: size * 0.2)
                            .offset(x: pupilOffset.x - size * 0.08, y: pupilOffset.y - size * 0.08)
                    )
            }
        }
        .animation(RobotAnimations.lookAnimation, value: lookDirection.x)
        .animation(RobotAnimations.lookAnimation, value: lookDirection.y)
    }
}

/// The robot's face (eyes + expression elements)
struct RobotFace: View {
    let expression: RobotExpression
    let lookDirection: CGPoint
    let eyeOpenAmount: CGFloat
    let size: CGFloat
    
    private var eyeSpacing: CGFloat { size * 0.28 }
    private var eyeSize: CGFloat { size * 0.22 }
    
    var body: some View {
        VStack(spacing: size * 0.06) {
            // Eyes
            HStack(spacing: eyeSpacing) {
                RobotEye(
                    size: eyeSize,
                    lookDirection: lookDirection,
                    openAmount: eyeOpenAmount,
                    isLeft: true
                )
                
                RobotEye(
                    size: eyeSize,
                    lookDirection: lookDirection,
                    openAmount: eyeOpenAmount,
                    isLeft: false
                )
            }
            
            // Mouth (expression-dependent)
            mouthView
                .opacity(expression == .idle ? 0.7 : 1.0)
        }
    }
    
    @ViewBuilder
    private var mouthView: some View {
        switch expression {
        case .happy:
            // Friendly smile arc
            HappyMouth(size: size)
            
        case .surprised:
            // Small O
            Circle()
                .fill(Color(hex: "1A1A2E").opacity(0.6))
                .frame(width: size * 0.08, height: size * 0.08)
            
        case .thinking:
            // Slight wavy line
            ThinkingMouth(size: size)
            
        case .talking:
            // Animated small shape
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: "1A1A2E").opacity(0.5))
                .frame(width: size * 0.1, height: size * 0.04)
            
        case .sleeping:
            // Tiny zzz
            Text("z")
                .font(.system(size: size * 0.08, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "7B8794"))
            
        case .curious:
            // Slight asymmetric line
            CuriousMouth(size: size)
            
        default:
            // Subtle neutral line
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: "1A1A2E").opacity(0.3))
                .frame(width: size * 0.12, height: 2)
        }
    }
}

// MARK: - Mouth Shapes

struct HappyMouth: View {
    let size: CGFloat
    
    var body: some View {
        Arc(startAngle: .degrees(10), endAngle: .degrees(170))
            .stroke(
                LinearGradient(
                    colors: [Color(hex: "1A1A2E").opacity(0.6), Color(hex: "1A1A2E").opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: size * 0.14, height: size * 0.06)
    }
}

struct ThinkingMouth: View {
    let size: CGFloat
    
    var body: some View {
        WavyLine()
            .stroke(Color(hex: "1A1A2E").opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size * 0.1, height: size * 0.03)
    }
}

struct CuriousMouth: View {
    let size: CGFloat
    
    var body: some View {
        Arc(startAngle: .degrees(160), endAngle: .degrees(200))
            .stroke(Color(hex: "1A1A2E").opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size * 0.1, height: size * 0.04)
            .rotationEffect(.degrees(10))
    }
}

struct WavyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        return path
    }
}

/// The complete robot character - Modern & Intelligent
struct RobotCharacter: View {
    let expression: RobotExpression
    let lookDirection: CGPoint
    let eyeOpenAmount: CGFloat
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(hex: "00D9FF").opacity(0.5),
                            Color(hex: "6C5CE7").opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: size + 4, height: size + 4)
                .blur(radius: 2)
            
            // Main body - sleek gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "667EEA"),
                            Color(hex: "764BA2")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color(hex: "764BA2").opacity(0.4), radius: 8, x: 0, y: 4)
            
            // Inner highlight - glass effect
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: size * 0.85, height: size * 0.85)
                .offset(x: -size * 0.05, y: -size * 0.05)
            
            // Face
            RobotFace(
                expression: expression,
                lookDirection: lookDirection,
                eyeOpenAmount: eyeOpenAmount,
                size: size
            )
            .offset(y: size * 0.02)
            
            // Status indicator light (top)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            statusColor.opacity(0.9),
                            statusColor.opacity(0.5)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 6, height: 6)
                .shadow(color: statusColor.opacity(0.6), radius: 4)
                .offset(y: -size * 0.42)
        }
    }
    
    private var statusColor: Color {
        switch expression {
        case .thinking: return Color(hex: "FDCB6E") // Yellow = processing
        case .happy: return Color(hex: "00CEC9") // Teal = positive
        case .sleeping: return Color(hex: "636E72") // Gray = standby
        default: return Color(hex: "00D9FF") // Cyan = ready
        }
    }
}

// MARK: - Helper Shapes

struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 15) {
            RobotCharacter(expression: .idle, lookDirection: .zero, eyeOpenAmount: 1, size: 48)
            RobotCharacter(expression: .happy, lookDirection: CGPoint(x: 0.5, y: 0), eyeOpenAmount: 1, size: 48)
            RobotCharacter(expression: .thinking, lookDirection: CGPoint(x: -0.5, y: 0.5), eyeOpenAmount: 1, size: 48)
        }
        HStack(spacing: 15) {
            RobotCharacter(expression: .surprised, lookDirection: .zero, eyeOpenAmount: 1, size: 48)
            RobotCharacter(expression: .curious, lookDirection: CGPoint(x: 0.3, y: -0.2), eyeOpenAmount: 1, size: 48)
            RobotCharacter(expression: .sleeping, lookDirection: .zero, eyeOpenAmount: 0.15, size: 48)
        }
    }
    .padding(30)
    .background(Color(hex: "1A1A2E"))
}

// Theme.swift
// Adventurers Harness — Visual Design System
//
// Defines the complete color palette, typography scale, spacing, and
// custom ViewModifiers that form the foundation of the TUI layer.
// macOS 15+ · Swift 6 · Sendable-safe

import SwiftUI

// MARK: - Color Palette

extension Color {
    // ─── Brand ───────────────────────────────────────────────────────────
    /// Adventurers Orange — primary accent
    static let adOrange      = Color(hex: 0xFF6B35)
    /// Deep Navy — primary background tone
    static let adNavy        = Color(hex: 0x0D1B2A)
    /// Midnight — darker surface
    static let adMidnight    = Color(hex: 0x1B2838)

    // ─── Semantic: Success ───────────────────────────────────────────────
    static let adSuccess     = Color(hex: 0x34D399)
    static let adSuccessDim  = Color(hex: 0x065F46)

    // ─── Semantic: Warning ──────────────────────────────────────────────
    static let adWarning     = Color(hex: 0xFBBF24)
    static let adWarningDim  = Color(hex: 0x78350F)

    // ─── Semantic: Error ─────────────────────────────────────────────────
    static let adError       = Color(hex: 0xF87171)
    static let adErrorDim    = Color(hex: 0x7F1D1D)

    // ─── Semantic: Info ──────────────────────────────────────────────────
    static let adInfo        = Color(hex: 0x60A5FA)
    static let adInfoDim     = Color(hex: 0x1E3A5F)

    // ─── Surfaces ────────────────────────────────────────────────────────
    static let adBackground  = Color(hex: 0x0D1117)
    static let adElevated    = Color(hex: 0x161B22)
    static let adOverlay     = Color(hex: 0x21262D)
    static let adCard        = Color(hex: 0x1C2128)
    static let adDivider     = Color.white.opacity(0.06)

    // ─── Text ────────────────────────────────────────────────────────────
    static let adTextPrimary   = Color(white: 0.95)
    static let adTextSecondary = Color(white: 0.65)
    static let adTextTertiary  = Color(white: 0.40)

    // ─── Gate Colors (permission gates) ──────────────────────────────────
    static let adSyntaxGate       = Color(hex: 0x60A5FA)  // blue
    static let adRepeatGate       = Color(hex: 0xA78BFA)  // purple
    static let adCompilationGate  = Color(hex: 0x34D399)  // green
    static let adMemoryGate       = Color(hex: 0xFB923C)  // orange
    static let adObjectiveGate    = Color(hex: 0xF87171)  // red

    // ─── Risk Levels (permission system) ─────────────────────────────────
    static let adRiskNone      = Color(white: 0.40)
    static let adRiskLow       = Color(hex: 0x34D399)
    static let adRiskMedium    = Color(hex: 0xFBBF24)
    static let adRiskHigh      = Color(hex: 0xFB923C)
    static let adRiskCritical  = Color(hex: 0xF87171)
}

// MARK: - Hex Initializer

extension Color {
    /// Creates a Color from a 24-bit hex integer (e.g. `0xFF6B35`).
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8)  & 0xFF) / 255.0,
            blue:  Double(hex         & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - Typography

extension Font {
    // ─── Display / Headings ──────────────────────────────────────────────
    /// 28pt bold — hero titles
    static let adTitle    = Font.system(size: 28, weight: .bold,    design: .rounded)
    /// 20pt semibold — section headings
    static let adHeading  = Font.system(size: 20, weight: .semibold, design: .rounded)
    /// 15pt medium — card titles
    static let adSubhead  = Font.system(size: 15, weight: .medium,  design: .rounded)

    // ─── Body ────────────────────────────────────────────────────────────
    /// 13pt regular — primary body text
    static let adBody     = Font.system(size: 13, weight: .regular, design: .default)
    /// 13pt medium — emphasis within body
    static let adBodyBold = Font.system(size: 13, weight: .medium,  design: .default)
    /// 11pt regular — secondary / caption text
    static let adCaption  = Font.system(size: 11, weight: .regular, design: .default)
    /// 11pt medium — labels, tags
    static let adLabel    = Font.system(size: 11, weight: .medium,  design: .rounded)

    // ─── Code ────────────────────────────────────────────────────────────
    /// 12pt monospaced — inline code, logs, terminal
    static let adCode     = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// 12pt monospaced bold — highlighted code
    static let adCodeBold = Font.system(size: 12, weight: .bold,    design: .monospaced)
}

// MARK: - Spacing Scale

/// Vertical / horizontal spacing tokens.
enum ADSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum ADCorner {
    static let sm:    CGFloat = 6
    static let md:    CGFloat = 10
    static let lg:    CGFloat = 14
    static let xl:    CGFloat = 20
    static let pill:  CGFloat = 999
}

// MARK: - Shadows

enum ADShadow {
    /// Subtle lift — cards, popovers
    static let lift = ShadowStyle(
        color: .black.opacity(0.25),
        radius: 8,
        x: 0,
        y: 2
    )
    /// Strong elevation — modals, tooltips
    static let elevation = ShadowStyle(
        color: .black.opacity(0.40),
        radius: 16,
        x: 0,
        y: 6
    )
    /// Glow — active / focused elements
    static func glow(_ color: Color, radius: CGFloat = 12) -> ShadowStyle {
        ShadowStyle(color: color.opacity(0.6), radius: radius, x: 0, y: 0)
    }

    struct ShadowStyle: Sendable {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
}

// MARK: - ViewModifiers

// ── Card Styling ─────────────────────────────────────────────────────────────

/// Applies the standard elevated card appearance: background, rounded corners,
/// and a subtle lift shadow.
struct CardStyle: ViewModifier {
    var padding: CGFloat = ADSpacing.lg
    var cornerRadius: CGFloat = ADCorner.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.adCard, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: ADShadow.lift.color,
                radius: ADShadow.lift.radius,
                x: ADShadow.lift.x,
                y: ADShadow.lift.y
            )
    }
}

extension View {
    /// Wraps the view in the standard card style.
    func adCard(
        padding: CGFloat = ADSpacing.lg,
        cornerRadius: CGFloat = ADCorner.md
    ) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// ── Glow Effect ──────────────────────────────────────────────────────────────

/// Adds a colored glow around the view, useful for active / focused indicators.
struct GlowEffect: ViewModifier {
    let color: Color
    var radius: CGFloat = 12
    var isActive: Bool = true

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(0.55) : .clear,
                radius: isActive ? radius : 0,
                x: 0,
                y: 0
            )
    }
}

extension View {
    /// Adds a colored glow when `isActive` is true.
    func adGlow(_ color: Color, radius: CGFloat = 12, isActive: Bool = true) -> some View {
        modifier(GlowEffect(color: color, radius: radius, isActive: isActive))
    }
}

// ── Pulse Animation ──────────────────────────────────────────────────────────

/// Applies a gentle scaling pulse animation. Typically used for recording
/// indicators, live status dots, or attention-grabbing badges.
struct PulseAnimation: ViewModifier {
    var minScale: CGFloat = 0.92
    var maxScale: CGFloat = 1.08
    var duration: Double = 1.4

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? maxScale : minScale)
            .animation(
                .easeInOut(duration: duration / 2)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

extension View {
    /// Adds a continuous pulse animation.
    func adPulse(
        minScale: CGFloat = 0.92,
        maxScale: CGFloat = 1.08,
        duration: Double = 1.4
    ) -> some View {
        modifier(PulseAnimation(minScale: minScale, maxScale: maxScale, duration: duration))
    }
}

// ── Skeleton Loading ─────────────────────────────────────────────────────────

/// Renders an animated gradient placeholder used for skeleton loading states.
struct SkeletonPlaceholder: ViewModifier {
    var cornerRadius: CGFloat = ADCorner.sm

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(0)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: Color.adOverlay, location: phase - 0.3),
                        .init(color: Color.adOverlay.opacity(0.5), location: phase),
                        .init(color: Color.adOverlay, location: phase + 0.3),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
                }
            )
            .clipped()
    }
}

extension View {
    /// Shows an animated skeleton placeholder.
    func adSkeleton(cornerRadius: CGFloat = ADCorner.sm) -> some View {
        modifier(SkeletonPlaceholder(cornerRadius: cornerRadius))
    }
}

// ── Tooltip ──────────────────────────────────────────────────────────────────

/// A lightweight tooltip popover shown on hover.
struct TooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: .top) {
                if isHovering {
                    Text(text)
                        .font(.adCaption)
                        .foregroundStyle(Color.adTextPrimary)
                        .padding(.horizontal, ADSpacing.sm)
                        .padding(.vertical, ADSpacing.xs)
                        .background(
                            Color.adOverlay,
                            in: RoundedRectangle(cornerRadius: ADCorner.sm)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        .offset(y: -4)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

extension View {
    /// Shows a tooltip on hover.
    func adTooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

// ── Overlay Dimming ──────────────────────────────────────────────────────────

/// A semi-transparent overlay used behind modals / sheets.
struct DimOverlay: ViewModifier {
    var opacity: Double = 0.5

    func body(content: Content) -> some View {
        content
            .overlay {
                Color.black.opacity(opacity)
                    .ignoresSafeArea()
            }
    }
}

extension View {
    /// Adds a dimming overlay (e.g. behind a modal).
    func adDimOverlay(opacity: Double = 0.5) -> some View {
        modifier(DimOverlay(opacity: opacity))
    }
}

// ── Risk Level Border ────────────────────────────────────────────────────────

/// Adds a colored left-border indicating risk level, used in permission lists.
struct RiskBorder: ViewModifier {
    let level: RiskLevel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(level.color)
                    .frame(width: 3)
            }
    }
}

extension View {
    /// Adds a risk-level accent border on the leading edge.
    func adRiskBorder(_ level: RiskLevel) -> some View {
        modifier(RiskBorder(level: level))
    }
}

// MARK: - Risk Level

/// Permission risk levels used across the permission system and gate UI.
enum RiskLevel: String, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high
    case critical

    var color: Color {
        switch self {
        case .none:     return .adRiskNone
        case .low:      return .adRiskLow
        case .medium:   return .adRiskMedium
        case .high:     return .adRiskHigh
        case .critical: return .adRiskCritical
        }
    }

    var label: String {
        switch self {
        case .none:     return "None"
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Gate Type

/// The five compilation / analysis gates in the Adventurers pipeline.
enum GateType: String, CaseIterable, Sendable {
    case syntax
    case repeat
    case compilation
    case memory
    case objective

    var color: Color {
        switch self {
        case .syntax:      return .adSyntaxGate
        case .repeat:      return .adRepeatGate
        case .compilation: return .adCompilationGate
        case .memory:      return .adMemoryGate
        case .objective:   return .adObjectiveGate
        }
    }

    var icon: String {
        switch self {
        case .syntax:      return "doc.text.magnifyingglass"
        case .repeat:      return "arrow.triangle.2.circlepath"
        case .compilation: return "hammer.fill"
        case .memory:      return "memorychip"
        case .objective:   return "target"
        }
    }

    var displayName: String {
        switch self {
        case .syntax:      return "Syntax"
        case .repeat:      return "Repeat"
        case .compilation: return "Compilation"
        case .memory:      return "Memory"
        case .objective:   return "Objective"
        }
    }
}

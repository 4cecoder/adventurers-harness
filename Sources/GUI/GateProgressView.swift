// TUI - Gate Progress Visualization
// Deterministic certification pipeline: the harness certifies, the model never decides.
// macOS 15+ | Swift 6 | @Observable

import SwiftUI
import Foundation
import AdventurersCore

// MARK: - Gate Status

/// Lifecycle state for a single gate node in the visualization.
enum GateStatus: Sendable, Equatable {
    /// Gate has not started evaluation.
    case pending
    /// Gate is currently evaluating.
    case running
    /// Gate passed certification.
    case passed
    /// Gate failed certification.
    case failed(errorCount: Int)

    var isTerminal: Bool {
        switch self {
        case .passed, .failed: return true
        default: return false
        }
    }

    var isSuccess: Bool {
        if case .passed = self { return true }
        return false
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

// MARK: - Gate Identifier

/// Canonical gate identifiers matching the AdventurersCore gate names.
enum GateIdentifier: String, Sendable, CaseIterable, Identifiable {
    case syntax = "syntax"
    case repeatDetection = "repeat"
    case compilation = "compilation"
    case memory = "memory"
    case diff = "diff"
    case objective = "objective"

    var id: String { rawValue }

    /// SF Symbol name for this gate.
    var symbolName: String {
        switch self {
        case .syntax:        "checkmark.braces"
        case .repeatDetection: "arrow.triangle.branch"
        case .compilation:   "hammer.fill"
        case .memory:        "memorychip"
        case .diff:          "doc.diff"
        case .objective:     "target"
        }
    }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .syntax:        "Syntax"
        case .repeatDetection: "Repeat"
        case .compilation:   "Compilation"
        case .memory:        "Memory"
        case .diff:          "Diff"
        case .objective:     "Objective"
        }
    }

    /// Tooltip description for the gate.
    var description: String {
        switch self {
        case .syntax:
            "Validates brace and parenthesis balance, extracts code from markdown fences."
        case .repeatDetection:
            "Rejects verbatim identical submissions to prevent infinite loops."
        case .compilation:
            "Compiles output to verify syntactic correctness against the target compiler."
        case .memory:
            "Audits memory allocations for leaks, excessive copies, and unbounded growth."
        case .diff:
            "Validates file changes are safe and won't corrupt existing code."
        case .objective:
            "Verifies the task contract deliverables are actually satisfied."
        }
    }
}

// MARK: - Gate Node Model

/// A single gate node's state for the visualization layer.
struct GateNode: Identifiable, Sendable {
    let id: GateIdentifier
    var status: GateStatus = .pending
    var result: GateResult?
    var elapsed: TimeInterval = 0

    var symbolName: String { id.symbolName }
    var displayName: String { id.displayName }
    var description: String { id.description }
}

// MARK: - Gate Pipeline State

/// Observable state container for the entire gate pipeline visualization.
///
/// The harness updates this as each gate evaluates. The view never drives evaluation.
@MainActor
final class GatePipelineState: ObservableObject {
    @Published var nodes: [GateNode]
    @Published var activeGateIndex: Int?
    @Published var allPassed: Bool?
    @Published var isDetailExpanded: Bool = false
    @Published var selectedGateID: GateIdentifier?
    @Published var totalElapsed: TimeInterval = 0

    init(gates: [GateIdentifier] = GateIdentifier.allCases) {
        self.nodes = gates.map { GateNode(id: $0) }
    }

    // MARK: - Pipeline Progress

    /// Fraction of gates that have reached a terminal state (0..1).
    var progress: Double {
        let terminalCount = nodes.filter(\.status.isTerminal).count
        return Double(terminalCount) / Double(nodes.count)
    }

    /// Number of passed gates.
    var passedCount: Int {
        nodes.filter(\.status.isSuccess).count
    }

    /// Number of failed gates.
    var failedCount: Int {
        nodes.filter(\.status.isFailure).count
    }

    // MARK: - State Transitions

    /// Mark a gate as currently running.
    func startGate(_ gateID: GateIdentifier) {
        guard let index = nodes.firstIndex(where: { $0.id == gateID }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            nodes[index].status = .running
            activeGateIndex = index
        }
    }

    /// Mark a gate as passed with its result.
    func passGate(_ gateID: GateIdentifier, result: GateResult, elapsed: TimeInterval) {
        guard let index = nodes.firstIndex(where: { $0.id == gateID }) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
            nodes[index].status = .passed
            nodes[index].result = result
            nodes[index].elapsed = elapsed
            if activeGateIndex == index {
                activeGateIndex = nil
            }
            totalElapsed += elapsed
        }
        checkCompletion()
    }

    /// Mark a gate as failed with its result and error count.
    func failGate(_ gateID: GateIdentifier, result: GateResult, errorCount: Int, elapsed: TimeInterval) {
        guard let index = nodes.firstIndex(where: { $0.id == gateID }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            nodes[index].status = .failed(errorCount: errorCount)
            nodes[index].result = result
            nodes[index].elapsed = elapsed
            if activeGateIndex == index {
                activeGateIndex = nil
            }
            totalElapsed += elapsed
        }
        checkCompletion()
    }

    /// Reset the entire pipeline to pending.
    func reset() {
        withAnimation(.easeInOut(duration: 0.3)) {
            nodes = nodes.map { var n = $0; n.status = .pending; n.result = nil; n.elapsed = 0; return n }
            activeGateIndex = nil
            allPassed = nil
            totalElapsed = 0
            selectedGateID = nil
        }
    }

    private func checkCompletion() {
        guard nodes.allSatisfy(\.status.isTerminal) else { return }
        allPassed = nodes.allSatisfy(\.status.isSuccess)
    }
}

// MARK: - Gate Node View

/// A single gate circle with symbol, state-dependent styling, and hover tooltip.
private struct GateNodeView: View {
    let node: GateNode
    let isActive: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var pulsePhase = false
    @State private var shakeOffset: CGFloat = 0
    @State private var particleOpacity: Double = 0

    private let nodeSize: CGFloat = 56
    private let symbolSize: CGFloat = 22

    var body: some View {
        ZStack {
            // Glow layer for passed/failed states
            glowLayer

            // Particle overlay for passed state
            particleOverlay

            // Main node circle
            circleBody
                .offset(x: shakeOffset)

            // Error count badge for failed state
            if case .failed(let count) = node.status {
                errorBadge(count)
            }

            // Running indicator
            if node.status == .running {
                runningRing
            }
        }
        .frame(width: nodeSize + 20, height: nodeSize + 20)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture { onTap() }
        .popover(isPresented: $isHovered) {
            tooltipContent
                .padding(12)
                .frame(maxWidth: 260)
        }
        .onChange(of: node.status) { _, newStatus in
            handleStatusChange(newStatus)
        }
    }

    // MARK: - Circle Body

    private var circleBody: some View {
        ZStack {
            Circle()
                .fill(backgroundFill)
                .frame(width: nodeSize, height: nodeSize)

            Circle()
                .strokeBorder(borderColor, lineWidth: borderWidth)
                .frame(width: nodeSize, height: nodeSize)

            Image(systemName: node.symbolName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .symbolEffect(.variableColor.iterative, value: node.status == .running)
        }
        .shadow(color: shadowColor.opacity(shadowOpacity), radius: shadowRadius)
    }

    // MARK: - Colors by State

    private var backgroundFill: Color {
        switch node.status {
        case .pending:   Color(nsColor: .controlBackgroundColor).opacity(0.6)
        case .running:   Color.orange.opacity(0.12)
        case .passed:    Color.green.opacity(0.15)
        case .failed:    Color.red.opacity(0.12)
        }
    }

    private var borderColor: Color {
        switch node.status {
        case .pending:   Color.secondary.opacity(0.3)
        case .running:   Color.orange
        case .passed:    Color.green
        case .failed:    Color.red
        }
    }

    private var borderWidth: CGFloat {
        switch node.status {
        case .running: 2.5
        case .passed: 2
        case .failed: 2
        case .pending: 1.5
        }
    }

    private var iconColor: Color {
        switch node.status {
        case .pending:   Color.secondary.opacity(0.5)
        case .running:   Color.orange
        case .passed:    Color.green
        case .failed:    Color.red
        }
    }

    private var shadowColor: Color {
        switch node.status {
        case .passed:    .green
        case .failed:    .red
        case .running:   .orange
        case .pending:   .clear
        }
    }

    private var shadowOpacity: Double {
        switch node.status {
        case .passed: 0.6
        case .failed: 0.5
        case .running: isHovered ? 0.5 : 0.3
        case .pending: 0
        }
    }

    private var shadowRadius: CGFloat {
        isHovered ? 14 : 10
    }

    // MARK: - Glow Layer

    @ViewBuilder
    private var glowLayer: some View {
        if node.status == .passed {
            Circle()
                .fill(Color.adSuccess.opacity(0.12))
                .frame(width: nodeSize + 8, height: nodeSize + 8)
        }
    }

    // MARK: - Particle Overlay (Empty)

    @ViewBuilder
    private var particleOverlay: some View {
        EmptyView()
    }

    // MARK: - Running Ring

    private var runningRing: some View {
        Circle()
            .stroke(Color.orange.opacity(0.4), lineWidth: 3)
            .frame(width: nodeSize + 8, height: nodeSize + 8)
            .rotationEffect(.degrees(pulsePhase ? 360 : 0))
            .animation(
                .linear(duration: 1.8).repeatForever(autoreverses: false),
                value: pulsePhase
            )
            .onAppear { pulsePhase = true }
    }

    // MARK: - Error Badge

    private func errorBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.red)
                    .shadow(color: .red.opacity(0.4), radius: 3)
            )
            .offset(x: nodeSize / 2 + 4, y: -nodeSize / 2 - 4)
    }

    // MARK: - Tooltip

    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(node.displayName)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(node.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Label(statusLabel, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if node.elapsed > 0 {
                    Spacer()
                    Text(node.elapsed, format: .number.precision(.fractionLength(2)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    + Text("s")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var statusLabel: String {
        switch node.status {
        case .pending:                  "Pending"
        case .running:                  "Running"
        case .passed:                   "Passed"
        case .failed(let count):        "Failed (\(count) error\(count == 1 ? "" : "s"))"
        }
    }

    private var statusIcon: String {
        switch node.status {
        case .pending:  "clock"
        case .running:  "arrow.triangle.2.circlepath"
        case .passed:   "checkmark.circle.fill"
        case .failed:   "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch node.status {
        case .pending:  .secondary
        case .running:  .orange
        case .passed:   .green
        case .failed:   .red
        }
    }

    // MARK: - Animations

    private func handleStatusChange(_ newStatus: GateStatus) {
        switch newStatus {
        case .failed:
            // Shake animation
            withAnimation(.easeInOut(duration: 0.08).repeatCount(5, autoreverses: true)) {
                shakeOffset = 6
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.15)) {
                    shakeOffset = 0
                }
            }
        case .passed:
            // Celebration burst
            pulsePhase = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                pulsePhase = true
            }
        default:
            break
        }
    }
}

// MARK: - Gate Connection View

/// Animated connecting line between two gate nodes.
private struct GateConnectionView: View {
    let fromStatus: GateStatus
    let toStatus: GateStatus
    let isActive: Bool

    @State private var dashPhase: CGFloat = 0

    private var lineColor: Color {
        if toStatus.isFailure { return .red.opacity(0.6) }
        if toStatus.isSuccess || isActive { return .green.opacity(0.6) }
        return Color.secondary.opacity(0.2)
    }

    private var lineWidth: CGFloat {
        isActive ? 2.5 : 1.5
    }

    var body: some View {
        Rectangle()
            .fill(lineColor)
            .frame(height: lineWidth)
            .frame(maxWidth: .infinity)
            .overlay(
                Rectangle()
                    .stroke(
                        Color.white.opacity(0.3),
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: [6, 4],
                            dashPhase: dashPhase
                        )
                    )
                    .frame(height: lineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .onAppear {
                if isActive {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        dashPhase = 10
                    }
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                        dashPhase = 10
                    }
                } else {
                    dashPhase = 0
                }
            }
    }
}

// MARK: - Gate Detail Panel

/// Collapsible panel showing detailed gate output/errors for the selected gate.
private struct GateDetailView: View {
    let node: GateNode
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Header
                    HStack(spacing: 8) {
                        Image(systemName: node.symbolName)
                            .foregroundStyle(statusColor)
                        Text("\(node.displayName) Gate")
                            .font(.headline)
                        Spacer()
                        statusChip
                    }

                    Divider()

                    // Result content
                    if let result = node.result {
                        if let error = result.error {
                            errorSection(error)
                        } else if !result.output.isEmpty {
                            outputSection(result.output)
                        }
                    } else if node.status == .pending {
                        Text("Waiting to evaluate...")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else if node.status == .running {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Evaluating...")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }

                    // Timing
                    if node.elapsed > 0 {
                        Divider()
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.tertiary)
                            Text("Completed in \(node.elapsed, format: .number.precision(.fractionLength(3)))s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
                        )
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)

            Text(error)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.08))
                )
        }
    }

    private func outputSection(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Output", systemImage: "doc.text")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)

            Text(output)
                .font(.caption)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.06))
                )
        }
    }

    private var statusChip: some View {
        Group {
            switch node.status {
            case .pending:
                Label("Pending", systemImage: "clock")
            case .running:
                Label("Running", systemImage: "arrow.triangle.2.circlepath")
            case .passed:
                Label("Passed", systemImage: "checkmark.circle.fill")
            case .failed(let count):
                Label("\(count) Error\(count == 1 ? "" : "s")", systemImage: "xmark.circle.fill")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.12))
        )
    }

    private var statusColor: Color {
        switch node.status {
        case .pending:  .secondary
        case .running:  .orange
        case .passed:   .green
        case .failed:   .red
        }
    }
}

// MARK: - Celebration Overlay

/// Full-screen confetti/sparkle overlay when all gates pass.
private struct CelebrationView: View {
    @State private var sparkles: [Sparkle] = []
    @State private var isVisible = false

    private let sparkleCount = 30

    var body: some View {
        ZStack {
            if isVisible {
                ForEach(sparkles) { sparkle in
                    sparkleView(sparkle)
                }
            }
        }
        .onAppear {
            generateSparkles()
            withAnimation(.easeIn(duration: 0.3)) {
                isVisible = true
            }
        }
    }

    private func sparkleView(_ sparkle: Sparkle) -> some View {
        Image(systemName: sparkle.symbol)
            .font(.system(size: sparkle.size))
            .foregroundStyle(sparkle.color)
            .offset(x: sparkle.x, y: sparkle.y)
            .opacity(sparkle.opacity)
            .scaleEffect(sparkle.scale)
            .rotationEffect(.degrees(sparkle.rotation))
    }

    private func generateSparkles() {
        let symbols = ["sparkle", "star.fill", "circle.fill", "diamond.fill"]
        let colors: [Color] = [.green, .yellow, .cyan, .mint, .white]

        sparkles = (0..<sparkleCount).map { i in
            let angle = Double(i) * (2 * .pi / Double(sparkleCount))
            let radius = Double.random(in: 40...160)
            return Sparkle(
                id: i,
                symbol: symbols.randomElement()!,
                color: colors.randomElement()!,
                size: CGFloat.random(in: 4...12),
                x: cos(angle) * radius,
                y: sin(angle) * radius - 40,
                opacity: 0,
                scale: 0.2,
                rotation: Double.random(in: 0...360)
            )
        }

        // Staggered entrance
        for i in sparkles.indices {
            let delay = Double(i) * 0.04
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(delay)) {
                sparkles[i].opacity = 1
                sparkles[i].scale = 1
                sparkles[i].y -= CGFloat.random(in: 10...40)
            }
            withAnimation(.easeOut(duration: 1.2).delay(delay + 0.5)) {
                sparkles[i].opacity = 0
                sparkles[i].y -= CGFloat.random(in: 30...60)
                sparkles[i].scale = 0.3
            }
        }
    }
}

private struct Sparkle: Identifiable {
    let id: Int
    let symbol: String
    let color: Color
    let size: CGFloat
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    var scale: CGFloat
    var rotation: Double
}

// MARK: - Main Gate Progress View

/// Horizontal gate pipeline visualization with connecting lines, detail panel, and progress bar.
///
/// Usage:
/// ```swift
/// let state = GatePipelineState()
/// GateProgressView(state: state)
/// ```
struct GateProgressView: View {
    @ObservedObject var state: GatePipelineState

    var body: some View {
        VStack(spacing: 0) {
            // Gate nodes row
            gateRow

            // Collapsible detail panel
            detailPanel

            Divider()

            // Overall progress bar
            progressBar
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
        .overlay(alignment: .center) {
            if state.allPassed == true {
                celebrationOverlay
            }
        }
    }

    // MARK: - Gate Row

    private var gateRow: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(state.nodes.enumerated()), id: \.element.id) { index, node in
                // Gate node
                GateNodeView(
                    node: node,
                    isActive: state.activeGateIndex == index,
                    isSelected: state.selectedGateID == node.id,
                    onTap: { toggleDetail(for: node.id) }
                )

                // Connection line (between nodes, not after last)
                if index < state.nodes.count - 1 {
                    let nextNode = state.nodes[index + 1]
                    GateConnectionView(
                        fromStatus: node.status,
                        toStatus: nextNode.status,
                        isActive: state.activeGateIndex == index
                            || state.activeGateIndex == index + 1
                    )
                    .frame(width: 32)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if let selectedID = state.selectedGateID,
               let node = state.nodes.first(where: { $0.id == selectedID }) {
                GateDetailView(
                    node: node,
                    isExpanded: state.isDetailExpanded
                )
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 8) {
            // Stats row
            HStack(spacing: 16) {
                // Passed
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(state.passedCount)/\(state.nodes.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Failed
                if state.failedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("\(state.failedCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                // Time
                if state.totalElapsed > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundStyle(.tertiary)
                        Text(state.totalElapsed, format: .number.precision(.fractionLength(2)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        + Text("s")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Status text
                if let allPassed = state.allPassed {
                    Text(allPassed ? "All Gates Passed" : "Pipeline Failed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(allPassed ? .green : .red)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressFillColor)
                        .frame(
                            width: geo.size.width * state.progress,
                            height: 8
                        )
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.progress)

                    // Shimmer on active
                    if state.activeGateIndex != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.3), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 60, height: 8)
                            .offset(x: shimmerOffset(in: geo.size.width))
                            .mask(
                                RoundedRectangle(cornerRadius: 4)
                                    .frame(width: geo.size.width * state.progress, height: 8)
                            )
                            .animation(
                                .linear(duration: 1.5).repeatForever(autoreverses: false),
                                value: state.progress
                            )
                    }
                }
            }
            .frame(height: 8)
        }
        .padding(.top, 10)
    }

    private var progressFillColor: Color {
        if let allPassed = state.allPassed {
            return allPassed ? .green : .red
        }
        return .orange
    }

    private func shimmerOffset(in width: CGFloat) -> CGFloat {
        // Simple position based on current progress
        return width * state.progress - 30
    }

    // MARK: - Celebration

    private var celebrationOverlay: some View {
        CelebrationView()
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func toggleDetail(for gateID: GateIdentifier) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if state.selectedGateID == gateID {
                state.isDetailExpanded.toggle()
            } else {
                state.selectedGateID = gateID
                state.isDetailExpanded = true
            }
        }
    }
}

// MARK: - Preview

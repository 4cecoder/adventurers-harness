// WorkbenchStatusBar.swift
// Adventurers Harness — Professional Status Bar with Live Metering & Telemetry
//
// Docked at the bottom of the workbench. Displays real-time TPS, TTFT, token breakdown,
// context window capacity gauge, cost estimation, sandbox state, and interactive telemetry drawer.
//
// macOS 15+ · Swift 6 · Sendable-safe

import SwiftUI
import AdventurersCore
import LLMProviders

// MARK: - Workbench Status Bar View

struct WorkbenchStatusBar: View {
    @Environment(AppState.self) private var appState
    let meteringState: ThreadMeteringState
    let gateState: GatePipelineState

    @State private var showingTelemetryPopover: Bool = false
    @State private var isHoveringContext: Bool = false
    @State private var isHoveringTps: Bool = false
    @State private var copiedToast: Bool = false

    init(meteringState: ThreadMeteringState, gateState: GatePipelineState) {
        self.meteringState = meteringState
        self.gateState = gateState
    }

    public var body: some View {
        HStack(spacing: 12) {
            // ── Left: Engine Status & Security Model ──
            leftStatusCluster

            Spacer(minLength: 8)

            // ── Center: Context Window Capacity Meter ──
            contextWindowMeter

            Spacer(minLength: 8)

            // ── Right: Live Metering & Telemetry Telemetry ──
            rightTelemetryCluster
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(minHeight: 28)
        .background(
            Color.adNavy
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.adDivider),
                    alignment: .top
                )
        )
        .popover(isPresented: $showingTelemetryPopover, arrowEdge: .bottom) {
            TelemetryDetailPopover(metering: meteringState, model: appState.settingsModel.selectedModel)
        }
    }

    // MARK: - Left Status Cluster

    @ViewBuilder
    private var leftStatusCluster: some View {
        HStack(spacing: 8) {
            // Live Status Indicator
            HStack(spacing: 5) {
                StatusDot(
                    color: meteringState.isStreaming ? Color.adWarning : Color.adSuccess,
                    size: 6,
                    isPulsing: meteringState.isStreaming
                )

                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(meteringState.isStreaming ? Color.adWarning : Color.adTextPrimary)
            }

            Text("•")
                .font(.system(size: 8))
                .foregroundStyle(Color.adTextTertiary)

            // Active Mode & Engine Chip
            HStack(spacing: 4) {
                if appState.settingsModel.executionMode == .metaHarness {
                    Image(systemName: appState.settingsModel.selectedMetaHarness.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.adInfo)

                    Text("Meta: \(appState.settingsModel.selectedMetaHarness.defaultBinaryName)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.adInfo)
                        .lineLimit(1)
                } else {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.adOrange)

                    Text(shortModelName(appState.settingsModel.selectedModel))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.adTextSecondary)
                        .lineLimit(1)
                }
            }

            Text("•")
                .font(.system(size: 8))
                .foregroundStyle(Color.adTextTertiary)

            // Darwin Sandbox Security Badge
            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.adSuccess)

                Text("Darwin Sandbox")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.adTextTertiary)
            }
            .help("Local Darwin Seatbelt sandbox active (Read: restricted, Write: repo only)")

            Text("•")
                .font(.system(size: 8))
                .foregroundStyle(Color.adTextTertiary)

            // Gates Status Chip
            gatesChip
        }
    }

    private var statusText: String {
        if meteringState.isStreaming {
            if meteringState.liveTTFTMs == nil {
                return "Connecting..."
            }
            return "Generating (Turn #\(meteringState.liveTurnNumber))"
        }
        return "Ready"
    }

    private func shortModelName(_ model: String) -> String {
        if model.isEmpty { return "Universal" }
        return model.components(separatedBy: "/").last ?? model
    }

    @ViewBuilder
    private var gatesChip: some View {
        let passedCount = gateState.nodes.filter { $0.status.isSuccess }.count
        let failedCount = gateState.nodes.filter { $0.status.isFailure }.count
        let totalCount = gateState.nodes.count

        HStack(spacing: 4) {
            Image(systemName: failedCount > 0 ? "xmark.shield.fill" : (passedCount == totalCount ? "checkmark.shield.fill" : "shield.checkered"))
                .font(.system(size: 9))
                .foregroundStyle(failedCount > 0 ? Color.adError : (passedCount > 0 ? Color.adSuccess : Color.adTextTertiary))

            Text("\(passedCount)/\(totalCount) Gates")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(failedCount > 0 ? Color.adError : (passedCount > 0 ? Color.adSuccess : Color.adTextTertiary))
        }
        .help("Deterministic Gate Certification: \(passedCount) passed, \(failedCount) failed of \(totalCount)")
    }

    // MARK: - Center Context Window Capacity Meter

    @ViewBuilder
    private var contextWindowMeter: some View {
        Button {
            showingTelemetryPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                    .font(.system(size: 9))
                    .foregroundStyle(meteringState.contextHealth.color)

                Text("Context:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.adTextTertiary)

                // Mini segmented progress track
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.adOverlay)
                        .frame(width: 54, height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(meteringState.contextHealth.color)
                        .frame(width: max(2, 54 * CGFloat(meteringState.contextUtilization)), height: 4)
                }

                Text("\(formatTokenK(meteringState.estimatedContextTokens)) / \(formatTokenK(meteringState.contextWindowLimit))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.adTextSecondary)

                Text("(\(meteringState.contextUtilizationPercentFormatted))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(meteringState.contextHealth.color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isHoveringContext ? Color.adOrange.opacity(0.3) : Color.adDivider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHoveringContext = $0 }
        .help("Context Window: \(meteringState.estimatedContextTokens) tokens used of \(meteringState.contextWindowLimit) max limit (\(meteringState.contextUtilizationPercentFormatted)). Click for full breakdown.")
    }

    private func formatTokenK(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    // MARK: - Right Telemetry Cluster

    @ViewBuilder
    private var rightTelemetryCluster: some View {
        HStack(spacing: 8) {
            // Live / Turn TPS badge
            tpsPill

            // TTFT Latency
            if meteringState.liveTTFTMs != nil || meteringState.lastTurnMetrics != nil {
                HStack(spacing: 3) {
                    Image(systemName: "stopwatch")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.adTextTertiary)
                    Text(meteringState.formattedLiveTTFT)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .help("Time to First Token (TTFT): initial response latency from provider")
            }

            // Duration
            if meteringState.isStreaming || meteringState.lastTurnMetrics != nil {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.adTextTertiary)
                    Text(meteringState.formattedLiveDuration)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .help("Generation elapsed duration for current/last turn")
            }

            // Token Ledger (Prompt / Completion)
            tokenLedgerPill

            // Cost Estimate
            costPill

            // Telemetry Popover Button
            Button {
                showingTelemetryPopover.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 9, weight: .bold))
                    Text("Telemetry")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(showingTelemetryPopover ? Color.adOrange.opacity(0.2) : Color.adElevated)
                .foregroundStyle(showingTelemetryPopover ? Color.adOrange : Color.adTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.adDivider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("View comprehensive metering breakdown, latency percentiles, and cost history")
        }
    }

    // MARK: - Pill Subcomponents

    @ViewBuilder
    private var tpsPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
                .foregroundStyle(meteringState.isStreaming ? Color.adWarning : (meteringState.lastTurnMetrics != nil ? Color.adSuccess : Color.adTextTertiary))

            Text(meteringState.formattedLiveTPS)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(meteringState.isStreaming ? Color.adTextPrimary : Color.adTextSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(meteringState.isStreaming ? Color.adWarning.opacity(0.15) : Color.adElevated)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .help("Tokens Per Second (TPS) throughput. Streaming real-time window / turn average.")
    }

    @ViewBuilder
    private var tokenLedgerPill: some View {
        let inTok = meteringState.isStreaming ? meteringState.cumulativePromptTokens : (meteringState.lastTurnMetrics?.promptTokens ?? meteringState.cumulativePromptTokens)
        let outTok = meteringState.isStreaming ? meteringState.liveGeneratedTokens : (meteringState.lastTurnMetrics?.completionTokens ?? meteringState.cumulativeCompletionTokens)

        HStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.adInfo)
                Text(formatTokenK(inTok))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.adTextSecondary)
            }

            HStack(spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.adSuccess)
                Text(formatTokenK(outTok))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.adTextSecondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.adElevated)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .help("Token meter: (↑ Input / Prompt tokens, ↓ Output / Generated tokens)")
    }

    @ViewBuilder
    private var costPill: some View {
        let cost = meteringState.isStreaming ? meteringState.liveCostUSD : (meteringState.lastTurnMetrics?.estimatedCostUSD ?? meteringState.cumulativeCostUSD)

        HStack(spacing: 3) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(Color.adWarning)

            Text(formatCost(cost))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.adTextPrimary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.adElevated)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .help("Estimated API spend calculated dynamically via model pricing table")
    }

    private func formatCost(_ val: Double) -> String {
        if val < 0.0001 {
            return "<$0.0001"
        } else if val < 0.01 {
            return String(format: "$%.4f", val)
        }
        return String(format: "$%.3f", val)
    }
}

// MARK: - Interactive Telemetry Detail Popover

struct TelemetryDetailPopover: View {
    let metering: ThreadMeteringState
    let model: String

    @State private var copiedSummary: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.adOrange)

                    Text("Harness Metering & Telemetry")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.adTextPrimary)
                }

                Spacer()

                Button {
                    copySummaryToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedSummary ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copiedSummary ? "Copied" : "Copy Report")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.adElevated)
                    .foregroundStyle(copiedSummary ? Color.adSuccess : Color.adTextSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Card 1: Last / Active Turn Telemetry
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT / LAST TURN METRICS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                Grid(horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        TelemetryMetricCell(label: "Throughput (TPS)", value: metering.formattedLiveTPS, icon: "bolt.fill", color: .adWarning)
                        TelemetryMetricCell(label: "Peak Speed", value: String(format: "%.1f tok/s", metering.peakTPS), icon: "flame.fill", color: .adOrange)
                    }
                    GridRow {
                        TelemetryMetricCell(label: "TTFT Latency", value: metering.formattedLiveTTFT, icon: "stopwatch", color: .adInfo)
                        TelemetryMetricCell(label: "Turn Duration", value: metering.formattedLiveDuration, icon: "clock", color: .adTextSecondary)
                    }
                    GridRow {
                        TelemetryMetricCell(label: "Prompt Tokens", value: "\(metering.lastTurnMetrics?.promptTokens ?? 0)", icon: "arrow.up", color: .adInfo)
                        TelemetryMetricCell(label: "Completion Tokens", value: "\(metering.lastTurnMetrics?.completionTokens ?? metering.liveGeneratedTokens)", icon: "arrow.down", color: .adSuccess)
                    }
                    if let reasoning = metering.lastTurnMetrics?.reasoningTokens, reasoning > 0 {
                        GridRow {
                            TelemetryMetricCell(label: "Reasoning Tokens", value: "\(reasoning)", icon: "brain.head.profile", color: .adRepeatGate)
                            TelemetryMetricCell(label: "Turn Cost", value: metering.lastTurnMetrics?.formattedCost ?? "$0.00", icon: "dollarsign.circle", color: .adWarning)
                        }
                    }
                }
                .padding(8)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Card 2: Cumulative Thread Session Ledger
            VStack(alignment: .leading, spacing: 6) {
                Text("THREAD CUMULATIVE LEDGER")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.adTextTertiary)

                Grid(horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        TelemetryMetricCell(label: "Total Turns", value: "\(metering.totalTurnsCount)", icon: "arrow.triangle.2.circlepath", color: .adTextPrimary)
                        TelemetryMetricCell(label: "Average TPS", value: String(format: "%.1f tok/s", metering.averageTPS), icon: "speedometer", color: .adSuccess)
                    }
                    GridRow {
                        TelemetryMetricCell(label: "Lifetime Tokens", value: metering.formattedCumulativeTokens, icon: "sum", color: .adInfo)
                        TelemetryMetricCell(label: "Total Est. Spend", value: metering.formattedCumulativeCost, icon: "creditcard", color: .adWarning)
                    }
                }
                .padding(8)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Card 3: Context Window Capacity & Allocation
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CONTEXT WINDOW CAPACITY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)

                    Spacer()

                    Text(metering.contextHealth.title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(metering.contextHealth.color)
                }

                VStack(spacing: 4) {
                    // Gauge bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.adOverlay)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(metering.contextHealth.color)
                                .frame(width: max(4, geo.size.width * CGFloat(metering.contextUtilization)), height: 8)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text("Used: \(metering.estimatedContextTokens) tok (\(metering.contextUtilizationPercentFormatted))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.adTextSecondary)

                        Spacer()

                        Text("Limit: \(metering.contextWindowLimit) tok")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.adTextTertiary)
                    }
                }
                .padding(8)
                .background(Color.adCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Card 4: Model Pricing Rate Table
            let spec = ModelPricingRegistry.shared.spec(for: model)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Family")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.adTextTertiary)
                    Text(spec.family)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.adTextPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Input / Output / 1M")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.adTextTertiary)
                    Text("$\(String(format: "%.2f", spec.inputCostPerMillion)) / $\(String(format: "%.2f", spec.outputCostPerMillion))")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.adTextSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .frame(width: 360)
        .background(Color.adBackground)
    }

    private func copySummaryToClipboard() {
        let summary = """
        ## Adventurers Harness Telemetry Report
        - **Model**: \(model)
        - **Live Throughput**: \(metering.formattedLiveTPS)
        - **Peak TPS**: \(String(format: "%.1f tok/s", metering.peakTPS))
        - **Average TPS**: \(String(format: "%.1f tok/s", metering.averageTPS))
        - **TTFT Latency**: \(metering.formattedLiveTTFT)
        - **Turn Duration**: \(metering.formattedLiveDuration)
        - **Context Utilization**: \(metering.estimatedContextTokens) / \(metering.contextWindowLimit) (\(metering.contextUtilizationPercentFormatted))
        - **Lifetime Tokens**: \(metering.formattedCumulativeTokens) (↑ \(metering.formattedCumulativePromptTokens), ↓ \(metering.formattedCumulativeCompletionTokens))
        - **Lifetime Est. Cost**: \(metering.formattedCumulativeCost)
        """
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(summary, forType: .string)
        #endif
        withAnimation { copiedSummary = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { copiedSummary = false }
        }
    }
}

// MARK: - Metric Cell

struct TelemetryMetricCell: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.adTextTertiary)

                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.adTextPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

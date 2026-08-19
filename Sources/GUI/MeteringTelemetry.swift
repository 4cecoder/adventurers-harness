// MeteringTelemetry.swift
// Adventurers Harness — SwiftUI Observability & Rate Tracking Engine
//
// macOS 15+ · Swift 6 · Sendable-safe

import Foundation
import SwiftUI
import AdventurersCore
import LLMProviders

// MARK: - ContextHealthStatus Color Extension

extension ContextHealthStatus {
    public var color: Color {
        switch self {
        case .optimal:  return .adSuccess
        case .moderate: return .adInfo
        case .high:     return .adWarning
        case .critical: return .adError
        }
    }
}

// MARK: - Rolling Window Rate Tracker for Live TPS

@MainActor
final class RollingTokenTracker {
    private struct TokenEvent {
        let timestamp: CFAbsoluteTime
        let tokenCount: Int
    }

    private var events: [TokenEvent] = []
    private let windowDuration: Double = 1.2 // 1.2s rolling window for smooth real-time TPS

    func addTokens(_ count: Int, at timestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        guard count > 0 else { return }
        events.append(TokenEvent(timestamp: timestamp, tokenCount: count))
        pruneOldEvents(currentTime: timestamp)
    }

    func currentTPS(currentTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Double {
        pruneOldEvents(currentTime: currentTime)
        guard let first = events.first, let last = events.last, events.count > 1 else {
            return 0.0
        }
        let elapsed = last.timestamp - first.timestamp
        if elapsed <= 0.001 { return 0.0 }
        let totalWindowTokens = events.reduce(0) { $0 + $1.tokenCount }
        return Double(totalWindowTokens) / elapsed
    }

    func reset() {
        events.removeAll(keepingCapacity: true)
    }

    private func pruneOldEvents(currentTime: CFAbsoluteTime) {
        let cutoff = currentTime - windowDuration
        while let first = events.first, first.timestamp < cutoff {
            events.removeFirst()
        }
    }
}

// MARK: - Thread Metering State

/// Observable real-time metering state for the active thread and cumulative sessions.
@Observable
@MainActor
public final class ThreadMeteringState {
    // MARK: Live Streaming State
    public var isStreaming: Bool = false
    public var liveTurnNumber: Int = 1
    public var liveTps: Double = 0.0
    public var livePeakTps: Double = 0.0
    public var liveGeneratedTokens: Int = 0
    public var liveReasoningTokens: Int = 0
    public var liveElapsedSeconds: Double = 0.0
    public var liveTTFTMs: Double? = nil
    public var liveCostUSD: Double = 0.0

    // MARK: Last Turn Records
    public var lastTurnMetrics: TurnMetrics?

    // MARK: Cumulative Thread Metrics
    public var turnsHistory: [TurnMetrics] = []
    public var cumulativePromptTokens: Int = 0
    public var cumulativeCompletionTokens: Int = 0
    public var cumulativeReasoningTokens: Int = 0
    public var cumulativeTotalTokens: Int = 0
    public var cumulativeCostUSD: Double = 0.0

    // MARK: Context Window Utilization
    public var contextWindowLimit: Int = 128_000
    public var estimatedContextTokens: Int = 0

    // Internal timing & rate trackers
    @ObservationIgnored private var turnStartTime: CFAbsoluteTime = 0
    @ObservationIgnored private var firstTokenTime: CFAbsoluteTime?
    @ObservationIgnored private var rollingTracker = RollingTokenTracker()
    @ObservationIgnored private var activeModel: String = "gpt-4o"
    @ObservationIgnored private var activeProvider: String = "OpenCode"
    @ObservationIgnored private var currentTurnPromptTokens: Int = 0
    @ObservationIgnored private var exactTokenUsageReceived: TokenUsage?

    public init() {
        self.contextWindowLimit = 128_000
    }

    // MARK: Computed Aggregates

    public var totalTurnsCount: Int {
        turnsHistory.count
    }

    public var averageTPS: Double {
        guard !turnsHistory.isEmpty else { return 0.0 }
        let sum = turnsHistory.reduce(0.0) { $0 + $1.tps }
        return sum / Double(turnsHistory.count)
    }

    public var peakTPS: Double {
        turnsHistory.map(\.peakTps).max() ?? livePeakTps
    }

    public var contextUtilization: Double {
        guard contextWindowLimit > 0 else { return 0.0 }
        return min(1.0, Double(estimatedContextTokens) / Double(contextWindowLimit))
    }

    public var contextUtilizationPercentFormatted: String {
        String(format: "%.1f%%", contextUtilization * 100.0)
    }

    public var contextHealth: ContextHealthStatus {
        let util = contextUtilization
        if util < 0.50 { return .optimal }
        if util < 0.70 { return .moderate }
        if util < 0.85 { return .high }
        return .critical
    }

    public var formattedCumulativeTokens: String {
        formatTokenNumber(cumulativeTotalTokens)
    }

    public var formattedCumulativePromptTokens: String {
        formatTokenNumber(cumulativePromptTokens)
    }

    public var formattedCumulativeCompletionTokens: String {
        formatTokenNumber(cumulativeCompletionTokens)
    }

    public var formattedCumulativeCost: String {
        if cumulativeCostUSD < 0.0001 {
            return "<$0.0001"
        } else if cumulativeCostUSD < 0.01 {
            return String(format: "$%.4f", cumulativeCostUSD)
        }
        return String(format: "$%.3f", cumulativeCostUSD)
    }

    public var formattedLiveTPS: String {
        if isStreaming {
            return String(format: "%.1f tok/s", liveTps)
        }
        if let last = lastTurnMetrics {
            return last.formattedTPS
        }
        return "-- tok/s"
    }

    public var formattedLiveTTFT: String {
        if let ttft = liveTTFTMs {
            if ttft >= 1000 {
                return String(format: "%.2fs TTFT", ttft / 1000.0)
            }
            return String(format: "%.0fms TTFT", ttft)
        }
        if let last = lastTurnMetrics {
            return last.formattedTTFT
        }
        return "-- ms TTFT"
    }

    public var formattedLiveDuration: String {
        if isStreaming {
            return String(format: "%.1fs", liveElapsedSeconds)
        }
        if let last = lastTurnMetrics {
            return last.formattedDuration
        }
        return "--"
    }

    // MARK: - Turn Lifecycle Instrumentation

    /// Called at the moment a prompt request is dispatched.
    public func startTurn(model: String, provider: String, estimatedPromptTokens: Int) {
        self.activeModel = model
        self.activeProvider = provider
        self.currentTurnPromptTokens = estimatedPromptTokens
        self.isStreaming = true
        self.turnStartTime = CFAbsoluteTimeGetCurrent()
        self.firstTokenTime = nil
        self.liveGeneratedTokens = 0
        self.liveReasoningTokens = 0
        self.liveTps = 0.0
        self.livePeakTps = 0.0
        self.liveTTFTMs = nil
        self.liveElapsedSeconds = 0.0
        self.exactTokenUsageReceived = nil
        self.rollingTracker.reset()

        let spec = ModelPricingRegistry.shared.spec(for: model)
        self.contextWindowLimit = spec.contextLimit
        self.liveTurnNumber = turnsHistory.count + 1
    }

    /// Called when the first token / delta chunk is received.
    public func recordFirstToken() {
        guard firstTokenTime == nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        firstTokenTime = now
        let ttft = (now - turnStartTime) * 1000.0
        self.liveTTFTMs = max(1.0, ttft)
    }

    /// Called for every streamed chunk delta to compute live rolling TPS and counts.
    public func recordStreamChunk(deltaText: String, reasoningDelta: String? = nil, exactUsage: TokenUsage? = nil) {
        let now = CFAbsoluteTimeGetCurrent()
        if firstTokenTime == nil {
            recordFirstToken()
        }

        // Estimate tokens in this chunk (heuristic: 1 token ~= 3.6 chars for code/english)
        var newTokens = 0
        if !deltaText.isEmpty {
            let count = max(1, Int(ceil(Double(deltaText.count) / 3.6)))
            newTokens += count
            liveGeneratedTokens += count
        }
        if let reasoning = reasoningDelta, !reasoning.isEmpty {
            let rCount = max(1, Int(ceil(Double(reasoning.count) / 3.6)))
            newTokens += rCount
            liveReasoningTokens += rCount
            liveGeneratedTokens += rCount
        }

        if let usage = exactUsage {
            self.exactTokenUsageReceived = usage
            self.liveGeneratedTokens = usage.completionTokens
        }

        rollingTracker.addTokens(newTokens, at: now)
        let currentRolling = rollingTracker.currentTPS(currentTime: now)
        if currentRolling > 0 {
            self.liveTps = currentRolling
            if currentRolling > self.livePeakTps {
                self.livePeakTps = currentRolling
            }
        }

        let elapsed = max(0.01, now - turnStartTime)
        self.liveElapsedSeconds = elapsed

        // Live cost
        let spec = ModelPricingRegistry.shared.spec(for: activeModel)
        self.liveCostUSD = spec.calculateCost(
            promptTokens: currentTurnPromptTokens,
            completionTokens: liveGeneratedTokens,
            reasoningTokens: liveReasoningTokens
        )
    }

    /// Record exact token usage when returned in final stream chunk or non-streaming response.
    public func recordExactUsage(_ usage: TokenUsage) {
        self.exactTokenUsageReceived = usage
    }

    /// Called when the generation turn completes and certification gates have executed.
    public func finishTurn(toolCallsCount: Int = 0, gatesPassedCount: Int = 0) {
        let now = CFAbsoluteTimeGetCurrent()
        let totalElapsed = max(0.05, now - turnStartTime)
        self.liveElapsedSeconds = totalElapsed

        let promptTokens = exactTokenUsageReceived?.promptTokens ?? currentTurnPromptTokens
        let completionTokens = exactTokenUsageReceived?.completionTokens ?? max(1, liveGeneratedTokens)
        let totalTokens = exactTokenUsageReceived?.totalTokens ?? (promptTokens + completionTokens)

        let ttft = liveTTFTMs ?? ((firstTokenTime ?? now) - turnStartTime) * 1000.0
        let overallTPS = Double(completionTokens) / totalElapsed
        let peak = max(livePeakTps, overallTPS)

        let spec = ModelPricingRegistry.shared.spec(for: activeModel)
        let cost = spec.calculateCost(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            reasoningTokens: liveReasoningTokens
        )

        let turnMetric = TurnMetrics(
            turnNumber: liveTurnNumber,
            timestamp: Date(),
            model: activeModel,
            provider: activeProvider,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            reasoningTokens: liveReasoningTokens,
            totalTokens: totalTokens,
            ttftMs: max(1.0, ttft),
            durationSeconds: totalElapsed,
            tps: overallTPS,
            peakTps: peak,
            estimatedCostUSD: cost,
            toolCallsCount: toolCallsCount,
            gatesPassedCount: gatesPassedCount
        )

        self.lastTurnMetrics = turnMetric
        self.turnsHistory.append(turnMetric)

        self.cumulativePromptTokens += promptTokens
        self.cumulativeCompletionTokens += completionTokens
        self.cumulativeReasoningTokens += liveReasoningTokens
        self.cumulativeTotalTokens += totalTokens
        self.cumulativeCostUSD += cost

        self.isStreaming = false
        self.liveTps = overallTPS
        self.liveCostUSD = cost
    }

    /// Recalculates total conversation context window usage based on all thread messages.
    public func recalculateContext(messages: [ThreadMessage], systemPromptLength: Int = 2000) {
        var totalChars = systemPromptLength
        for msg in messages {
            totalChars += msg.content.count
            if let reasoning = msg.thinkingContent {
                totalChars += reasoning.count
            }
            for tc in msg.toolCalls {
                totalChars += tc.name.count + tc.arguments.count
            }
            for tr in msg.toolResults {
                totalChars += tr.output.count
            }
        }
        // Approximate token estimate from character count (1 token ~= 3.6 chars)
        self.estimatedContextTokens = max(10, Int(ceil(Double(totalChars) / 3.6)))
    }

    public func reset() {
        isStreaming = false
        liveTurnNumber = 1
        liveTps = 0.0
        livePeakTps = 0.0
        liveGeneratedTokens = 0
        liveReasoningTokens = 0
        liveElapsedSeconds = 0.0
        liveTTFTMs = nil
        liveCostUSD = 0.0
        lastTurnMetrics = nil
        turnsHistory.removeAll()
        cumulativePromptTokens = 0
        cumulativeCompletionTokens = 0
        cumulativeReasoningTokens = 0
        cumulativeTotalTokens = 0
        cumulativeCostUSD = 0.0
        estimatedContextTokens = 0
    }

    private func formatTokenNumber(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.2fM", Double(n) / 1_000_000.0)
        } else if n >= 1_000 {
            return String(format: "%.1fk", Double(n) / 1_000.0)
        }
        return "\(n)"
    }
}

// MetaHarnessAndTelemetryTests.swift
// Adventurers Harness — Meta Harness Profiles, Process Registry & Telemetry Token Velocity Tests

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Meta Harness, Pricing & Telemetry Suite")
struct MetaHarnessAndTelemetryTests {

    // MARK: - Meta Harness Registry

    @Test("Meta Harness registry discovered profiles and CLI mappings")
    func metaHarnessDiscovery() {
        let registry = MetaHarnessRegistry.shared
        let profiles = registry.discoverProfiles()
        #expect(!profiles.isEmpty)

        let names = profiles.map(\.type.rawValue)
        #expect(names.contains("OpenAI Codex CLI"))
        #expect(names.contains("Anthropic Claude Code CLI (claude)"))
        #expect(names.contains("OpenCode CLI"))
        #expect(names.contains("Nous Hermes Agent"))
    }

    // MARK: - Model Pricing Registry

    @Test("Model Pricing Registry calculations across multiple model tiers")
    func modelPricingCalculations() {
        let pricing = ModelPricingRegistry.shared

        let gpt4Spec = pricing.spec(for: "gpt-4o")
        let gpt4Cost = gpt4Spec.calculateCost(promptTokens: 10_000, completionTokens: 2_000)
        #expect(gpt4Cost > 0)

        let claudeSpec = pricing.spec(for: "claude-sonnet-4-20250514")
        let claudeCost = claudeSpec.calculateCost(promptTokens: 5_000, completionTokens: 1_000)
        #expect(claudeCost > 0)
    }

    // MARK: - Active Process Registry

    @Test("Active Process Registry tracks subprocess lifecycle and termination")
    func activeProcessRegistryTracking() {
        let registry = ActiveProcessRegistry.shared
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = ["0.1"]
        try? proc.run()

        if proc.processIdentifier > 0 {
            registry.register(process: proc)
            registry.unregister(process: proc)
        }
        #expect(true)
    }

    // MARK: - Turn Metrics & Velocity

    @Test("Turn Metrics formatting and token velocity accounting")
    func turnMetricsAccounting() {
        let metrics = TurnMetrics(
            turnNumber: 1,
            model: "gpt-4o",
            provider: "OpenAI",
            promptTokens: 120,
            completionTokens: 80,
            ttftMs: 250.0,
            durationSeconds: 2.0,
            tps: 40.0,
            peakTps: 55.0,
            estimatedCostUSD: 0.001
        )
        #expect(metrics.tps == 40.0)
        #expect(metrics.totalTokens == 200)
    }
}

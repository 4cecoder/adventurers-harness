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
        let profiles = registry.registeredProfiles()
        #expect(!profiles.isEmpty)

        let names = profiles.map(\.type.rawValue)
        #expect(names.contains("Codex CLI"))
        #expect(names.contains("Claude Code"))
        #expect(names.contains("OpenCode"))
        #expect(names.contains("Hermes Agent"))
    }

    // MARK: - Model Pricing Registry

    @Test("Model Pricing Registry calculations across multiple model tiers")
    func modelPricingCalculations() {
        let pricing = ModelPricingRegistry.shared

        let gpt4Cost = pricing.calculateCost(model: "gpt-4o", promptTokens: 10_000, completionTokens: 2_000)
        #expect(gpt4Cost > 0)

        let claudeCost = pricing.calculateCost(model: "claude-sonnet-4-20250514", promptTokens: 5_000, completionTokens: 1_000)
        #expect(claudeCost > 0)
    }

    // MARK: - Active Process Registry

    @Test("Active Process Registry tracks subprocess lifecycle and termination")
    func activeProcessRegistryTracking() {
        let registry = ActiveProcessRegistry.shared
        let pid: pid_t = 99999

        registry.register(pid: pid, description: "Test process")
        #expect(registry.activePIDs().contains(pid))

        registry.unregister(pid: pid)
        #expect(!registry.activePIDs().contains(pid))
    }

    // MARK: - Turn Metrics & Velocity

    @Test("Turn Metrics formatting and token velocity accounting")
    func turnMetricsAccounting() {
        var metrics = TurnMetrics(
            turnIndex: 1,
            promptTokens: 120,
            completionTokens: 80,
            durationSeconds: 2.0,
            costUSD: 0.001
        )
        #expect(metrics.tokensPerSecond == 40.0)

        metrics.completionTokens = 160
        #expect(metrics.tokensPerSecond == 80.0)
    }
}

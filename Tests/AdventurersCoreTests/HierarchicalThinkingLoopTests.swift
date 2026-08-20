// HierarchicalThinkingLoopTests.swift
// AdventurersCoreTests — Unit Tests for Tri-Tier Hierarchical Thinking Loop

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Hierarchical Thinking Loop & Model Tiers Suite")
struct HierarchicalThinkingLoopTests {

    @Test("ModelTier exposes calibrated expected TPS and latency targets")
    func modelTierPerformanceSpecs() {
        #expect(ModelTier.tier1_needle2.expectedTPS >= 900.0)
        #expect(ModelTier.tier2_midWorkhorse.expectedTPS >= 200.0)
        #expect(ModelTier.tier3_bonsai27b.expectedTPS <= 100.0)

        #expect(ModelTier.tier1_needle2.latencyTargetMs <= 20.0)
    }

    @Test("HierarchicalThinkingLoop resolves fast-path queries directly in Tier 1")
    func tier1FastPathResolution() async {
        let loop = HierarchicalThinkingLoop()
        let steps = await loop.evaluateQuery(prompt: "git status")

        #expect(steps.count == 1)
        #expect(steps[0].activeTier == .tier1_needle2)
        #expect(steps[0].stage == .localFastPath)
        #expect(steps[0].verificationPassed == true)
    }

    @Test("HierarchicalThinkingLoop routes generative requests to Tier 2 for high-throughput drafting")
    func tier2MidTierDrafting() async {
        let loop = HierarchicalThinkingLoop()
        let steps = await loop.evaluateQuery(prompt: "Write a Swift function to calculate Fibonacci numbers")

        #expect(steps.count >= 2)
        #expect(steps[0].stage == .intentRouting)
        #expect(steps[1].activeTier == .tier2_midWorkhorse)
        #expect(steps[1].stage == .midTierDrafting)
    }

    @Test("HierarchicalThinkingLoop escalates to Tier 3 Bonsai 27B on verification gate failure")
    func tier3BonsaiEscalationOnGateFailure() async {
        let loop = HierarchicalThinkingLoop()
        let steps = await loop.evaluateQuery(
            prompt: "Refactor concurrency actor boundary",
            simulateGateFailure: true
        )

        #expect(steps.count == 3)
        #expect(steps[0].activeTier == .tier1_needle2)
        #expect(steps[1].activeTier == .tier2_midWorkhorse)
        #expect(steps[1].verificationPassed == false)
        #expect(steps[2].activeTier == .tier3_bonsai27b)
        #expect(steps[2].stage == .deepReasoningEscalation)
        #expect(steps[2].verificationPassed == true)
    }
}

// AdventurersCoreTests - GuardianCircuitBreaker and KnowledgeRegistry Test Suite

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Guardian Circuit Breaker & OKF Knowledge Registry Suite")
struct GuardianAndKnowledgeTests {

    @Test("Guardian Circuit Breaker trips after consecutive failure threshold and denies fail-closed")
    func testGuardianConsecutiveFailures() async {
        let guardian = GuardianCircuitBreaker(maxConsecutiveFailures: 3, slidingWindowSize: 20, maxWindowFailures: 5)

        // Turn 1 fails
        await guardian.recordExecution(success: false, errorDescription: "Compilation error")
        var decision = await guardian.evaluate(command: "swift build", toolName: "bash")
        #expect(decision == .allow)

        // Turn 2 fails
        await guardian.recordExecution(success: false, errorDescription: "Link error")
        decision = await guardian.evaluate(command: "swift build", toolName: "bash")
        #expect(decision == .allow)

        // Turn 3 fails -> trips circuit
        await guardian.recordExecution(success: false, errorDescription: "Fatal crash")
        decision = await guardian.evaluate(command: "swift build", toolName: "bash")

        if case .deny(_, let circuitTripped) = decision {
            #expect(circuitTripped == true)
        } else {
            Issue.record("Expected circuit breaker to deny when tripped")
        }

        // Reset circuit
        await guardian.resetCircuit()
        decision = await guardian.evaluate(command: "swift build", toolName: "bash")
        #expect(decision == .allow)
    }

    @Test("Guardian Circuit Breaker trips on sliding window failure density")
    func testGuardianWindowDensity() async {
        let guardian = GuardianCircuitBreaker(maxConsecutiveFailures: 10, slidingWindowSize: 10, maxWindowFailures: 4)

        // 3 failures interspersed with success
        await guardian.recordExecution(success: false)
        await guardian.recordExecution(success: true)
        await guardian.recordExecution(success: false)
        await guardian.recordExecution(success: true)
        await guardian.recordExecution(success: false)

        var decision = await guardian.evaluate(command: "test", toolName: "bash")
        #expect(decision == .allow)

        // 4th failure in 10 turns -> trips window threshold
        await guardian.recordExecution(success: false)
        decision = await guardian.evaluate(command: "test", toolName: "bash")

        if case .deny(_, let circuitTripped) = decision {
            #expect(circuitTripped == true)
        } else {
            Issue.record("Expected window density to trip circuit")
        }
    }

    @Test("OKF Knowledge Registry indexes and matches packets with semantic score ranking")
    func testKnowledgeRegistryMatching() async {
        let registry = KnowledgeRegistry.shared

        let packets = await registry.matchPackets(for: "How do I fix swift6 actor isolation compiler errors?")
        #expect(!packets.isEmpty)
        #expect(packets.first?.id == "swift6-concurrency")
        #expect(packets.first?.tags.contains("swift6") == true)

        let diffPackets = await registry.matchPackets(for: "patch context mismatch rollback")
        #expect(!diffPackets.isEmpty)
        #expect(diffPackets.first?.id == "diff-engine-safety")
    }
}

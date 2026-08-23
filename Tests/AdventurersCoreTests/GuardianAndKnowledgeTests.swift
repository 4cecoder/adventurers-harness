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

    @Test("KnowledgeRegistry persists ingested packets to disk and reloads them on relaunch")
    func testKnowledgeRegistryPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adventurers-knowledge-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = KnowledgeRegistry(directoryOverride: tempDir)
        let packet = await registry.ingest(
            title: "Deploying to TestFlight",
            content: "Run scripts/package_app.sh, then upload via altool.",
            tags: ["deploy", "testflight"]
        )

        #expect(await registry.getPacket(id: packet.id)?.title == "Deploying to TestFlight")
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("\(packet.id).json").path))

        // A fresh registry instance pointed at the same directory should pick it up — this is the
        // actual "survives relaunch" behavior, not just "stays in memory for this instance."
        let reloaded = KnowledgeRegistry(directoryOverride: tempDir)
        #expect(await reloaded.getPacket(id: packet.id)?.content.contains("altool") == true)

        await registry.deletePacket(id: packet.id)
        #expect(await registry.getPacket(id: packet.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("\(packet.id).json").path))
    }
}

// HindsightDockerGateTests.swift
// AdventurersCoreTests — Unit Tests for Hindsight Docker Gate

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Hindsight Docker Gate Suite")
struct HindsightDockerGateTests {

    @Test("HindsightDockerGate returns false safely when no local Docker container is running")
    func dockerOfflineSafety() {
        // Port 59999 is intentionally unused to test offline non-blocking safety
        let gate = HindsightDockerGate(dockerPort: 59999, timeoutSeconds: 0.05)
        let isAvailable = gate.isDockerHindsightAvailable()
        #expect(isAvailable == false)
    }
}

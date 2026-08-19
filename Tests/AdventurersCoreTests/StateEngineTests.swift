// StateEngineTests.swift
// Adventurers Harness — State Engine Lifecycle & Illegal Transition Tests

import Testing
import Foundation
@testable import AdventurersCore

@Suite("State Engine Lifecycle Suite")
struct StateEngineTests {

    @Test("State Engine valid full lifecycle progression")
    func stateEngineFullLifecycle() async throws {
        let engine = StateEngine()
        #expect(await engine.currentState == .idle)

        try await engine.transition(to: .planning)
        #expect(await engine.currentState == .planning)

        try await engine.transition(to: .executing)
        #expect(await engine.currentState == .executing)

        try await engine.transition(to: .gating)
        #expect(await engine.currentState == .gating)

        try await engine.transition(to: .completed)
        #expect(await engine.currentState == .completed)
    }

    @Test("State Engine rejects invalid state skips and illegal transitions")
    func stateEngineIllegalTransitions() async {
        let engine = StateEngine()
        #expect(await engine.currentState == .idle)

        await #expect(throws: StateEngineError.self) {
            try await engine.transition(to: .completed)
        }

        await #expect(throws: StateEngineError.self) {
            try await engine.transition(to: .gating)
        }
    }

    @Test("State Engine gating rejection and re-proposing loop")
    func stateEngineGatingLoop() async throws {
        let engine = StateEngine()
        try await engine.transition(to: .planning)
        try await engine.transition(to: .executing)
        try await engine.transition(to: .gating)

        try await engine.transition(to: .reProposing)
        #expect(await engine.currentState == .reProposing)

        try await engine.transition(to: .executing)
        #expect(await engine.currentState == .executing)
    }
}

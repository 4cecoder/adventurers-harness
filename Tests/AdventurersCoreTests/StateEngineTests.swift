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
        #expect(await engine.current() == .idle)

        try await engine.transition(to: .taskingested)
        #expect(await engine.current() == .taskingested)

        try await engine.transition(to: .proposing)
        #expect(await engine.current() == .proposing)

        try await engine.transition(to: .validatingSyntax)
        #expect(await engine.current() == .validatingSyntax)

        try await engine.transition(to: .compiling)
        #expect(await engine.current() == .compiling)

        try await engine.transition(to: .executingTest)
        #expect(await engine.current() == .executingTest)

        try await engine.transition(to: .verified)
        #expect(await engine.current() == .verified)

        try await engine.transition(to: .idle)
        #expect(await engine.current() == .idle)
    }

    @Test("State Engine rejects invalid state skips and illegal transitions")
    func stateEngineIllegalTransitions() async {
        let engine = StateEngine()
        #expect(await engine.current() == .idle)

        await #expect(throws: StateError.self) {
            try await engine.transition(to: .verified)
        }

        await #expect(throws: StateError.self) {
            try await engine.transition(to: .compiling)
        }
    }

    @Test("State Engine gating rejection and retrying loop")
    func stateEngineGatingLoop() async throws {
        let engine = StateEngine()
        try await engine.transition(to: .taskingested)
        try await engine.transition(to: .proposing)
        try await engine.transition(to: .validatingSyntax)

        try await engine.transition(to: .retrying)
        #expect(await engine.current() == .retrying)

        try await engine.transition(to: .proposing)
        #expect(await engine.current() == .proposing)
    }
}

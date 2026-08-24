// BiomimeticMemoryTests.swift
// Adventurers Harness — Unit Tests for Native Biomimetic Memory Engine

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Biomimetic Cognitive Memory Suite")
struct BiomimeticMemoryTests {

    @Test("Engine retains world facts, experience facts, and mental models with dense embeddings")
    func testRetainAndRecallHierarchy() async {
        let engine = BiomimeticMemoryEngine()

        // 1. Retain World Fact
        await engine.retain(
            type: .worldFact,
            title: "Strict Swift 6 Mode",
            content: "The codebase enforces Swift 6 strict concurrency across all targets without warnings.",
            tags: ["swift6", "concurrency"]
        )

        // 2. Retain Experience Fact
        await engine.retain(
            type: .experienceFact,
            title: "Refactored NeedleProcessor tests",
            content: "Expanded pattern coverage for build commands and file creation in NeedleProcessorTests.",
            tags: ["needle", "tests"]
        )

        // 3. Retain Mental Model
        await engine.retain(
            type: .mentalModel,
            title: "Architecture: Hybrid Local Fast-Path",
            content: "Requests <15ms are resolved on-device via Tier 1 Cactus Needle 2; complex multi-step reasoning escalates to cloud frontier models.",
            tags: ["architecture", "routing"]
        )

        let count = await engine.count
        #expect(count == 3)

        // 4. Recall via hybrid semantic search
        let results = await engine.recall(query: "concurrency rules and swift 6", topK: 2)
        #expect(!results.isEmpty)
        #expect(results.first?.title == "Strict Swift 6 Mode")

        // 5. Reflect across memory records
        let reflection = await engine.reflect(query: "how does needle route commands?")
        #expect(reflection.contains("🧠 Native Swift Cognitive Reflection"))
        #expect(reflection.contains("Needle") || reflection.contains("Hybrid Local Fast-Path"))
    }
}

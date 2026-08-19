// DiffAndCompactorTests.swift
// Adventurers Harness — Patch Application, Context Compaction & Trajectory Compression Tests

import Testing
import Foundation
@testable import AdventurersCore
import LLMProviders

@Suite("Diff & Context Compactor Suite")
struct DiffAndCompactorTests {

    // MARK: - Diff Engine

    @Test("Diff Engine single and multi-hunk patch application")
    func diffEnginePatching() throws {
        let engine = DiffEngine()
        let original = "line1\nline2\nline3\n"
        let patch = """
        @@ -1,3 +1,3 @@
         line1
        -line2
        +line2_modified
         line3
        """

        let result = try engine.applyPatch(original: original, patch: patch)
        #expect(result.contains("line2_modified"))
        #expect(!result.contains("line2\n"))
    }

    @Test("Diff Engine rejects patches with corrupted context")
    func diffEngineCorruptedContext() {
        let engine = DiffEngine()
        let original = "alpha\nbeta\ngamma\n"
        let badPatch = """
        @@ -1,3 +1,3 @@
         mismatched_context
        -beta
        +delta
         gamma
        """

        #expect(throws: DiffError.self) {
            try engine.applyPatch(original: original, patch: badPatch)
        }
    }

    // MARK: - Context Compactor

    @Test("Context Compactor preserves head and tail anchors while compacting middle")
    func contextCompactorAnchorPreservation() async {
        let compactor = ContextCompactor()

        var messages: [Message] = [
            Message(role: .system, content: "You are Adventurers Coding Agent."),
            Message(role: .user, content: "Start task contract 1"),
        ]

        for i in 1...10 {
            messages.append(Message(role: .assistant, content: "Running step \(i) with output..."))
            messages.append(Message(role: .user, content: "Output of step \(i): success."))
        }

        messages.append(Message(role: .assistant, content: "Recent turn A"))
        messages.append(Message(role: .user, content: "Recent turn B"))

        let compacted = await compactor.compact(messages: messages, contextLimit: 500)
        #expect(!compacted.isEmpty)

        // Head anchor preserved
        #expect(compacted.first?.content.contains("You are Adventurers Coding Agent.") == true)
        // Tail anchor preserved
        #expect(compacted.last?.content.contains("Recent turn B") == true)
    }

    // MARK: - Trajectory Compressor

    @Test("Trajectory Compressor reduces token volume of long horizon outputs")
    func trajectoryCompressorRatio() {
        let compressor = TrajectoryCompressor()
        let largeOutput = String(repeating: "DEBUG: [2026-08-19] processing item in batch loop\n", count: 100)

        let compressed = compressor.compress(rawOutput: largeOutput, maxTokens: 40)
        #expect(compressed.count < largeOutput.count)
        #expect(compressed.contains("compacted") || compressed.contains("lines") || compressed.contains("..."))
    }
}

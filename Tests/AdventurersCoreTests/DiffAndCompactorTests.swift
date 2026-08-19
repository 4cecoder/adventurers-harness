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
        let rawDiff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,3 @@
         line1
        -line2
        +line2_modified
         line3
        """

        let patches = engine.parseUnifiedDiff(rawDiff)
        #expect(!patches.isEmpty)

        let result = try engine.apply(originalContent: original, hunks: patches[0].hunks)
        #expect(result.contains("line2_modified"))
        #expect(!result.contains("line2\n"))
    }

    @Test("Diff Engine rejects patches with corrupted context")
    func diffEngineCorruptedContext() {
        let engine = DiffEngine()
        let original = "alpha\nbeta\ngamma\n"
        let badDiff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,3 @@
         mismatched_context
        -beta
        +delta
         gamma
        """

        let patches = engine.parseUnifiedDiff(badDiff)
        #expect(!patches.isEmpty)

        #expect(throws: Error.self) {
            try engine.apply(originalContent: original, hunks: patches[0].hunks)
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
    func trajectoryCompressorRatio() async {
        let compressor = TrajectoryCompressor(config: TrajectoryCompressionConfig(targetMaxTokens: 50, protectedHeadTurns: 1, protectedTailTurns: 1))
        
        var turns: [TrajectoryTurn] = [
            TrajectoryTurn(role: "user", content: "Initial prompt"),
        ]
        for i in 1...10 {
            turns.append(TrajectoryTurn(role: "tool", content: "Tool output \(i) with lots of debug logs and data \(String(repeating: "xyz ", count: 20))"))
        }
        turns.append(TrajectoryTurn(role: "assistant", content: "Final answer"))

        let compressed = await compressor.compressTrajectory(turns)
        #expect(compressed.count < turns.count)
        #expect(compressed.first?.content == "Initial prompt")
        #expect(compressed.last?.content == "Final answer")
    }
}

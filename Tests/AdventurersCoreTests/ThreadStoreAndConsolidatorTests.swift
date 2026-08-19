// ThreadStoreAndConsolidatorTests.swift
// Adventurers Harness — Thread Persistence & Message Compaction / Consolidation Tests

import Testing
import Foundation
@testable import AdventurersCore
@testable import GUI

@Suite("Thread Message Consolidation & Persistence Suite")
struct ThreadStoreAndConsolidatorTests {

    @Test("Thread Message Consolidator merges consecutive multi-turn agent tool executions")
    @MainActor
    func testThreadMessageConsolidation() {
        let now = Date()
        let call1 = ThreadToolCall(id: "c1", name: "read_file", arguments: "file: a.swift", status: .succeeded(output: "content A"))
        let res1 = ThreadToolResult(id: "r1", toolCallID: "c1", output: "content A", isError: false)
        let msg1 = ThreadMessage(
            id: "m1",
            role: .agent,
            content: "Reading file...",
            timestamp: now,
            toolCalls: [call1],
            toolResults: [res1],
            isStreaming: false
        )

        let call2 = ThreadToolCall(id: "c2", name: "edit_file", arguments: "file: a.swift", status: .succeeded(output: "patched"))
        let res2 = ThreadToolResult(id: "r2", toolCallID: "c2", output: "patched", isError: false)
        let msg2 = ThreadMessage(
            id: "m2",
            role: .agent,
            content: "I have applied the fix to a.swift.",
            timestamp: now.addingTimeInterval(5),
            toolCalls: [call2],
            toolResults: [res2],
            isStreaming: false
        )

        let input = [msg1, msg2]
        let consolidated = ThreadMessageConsolidator.consolidate(input)

        #expect(consolidated.count == 1)
        #expect(consolidated[0].toolCalls.count == 2)
        #expect(consolidated[0].toolResults.count == 2)
        #expect(consolidated[0].content == "I have applied the fix to a.swift.")
    }

    @Test("Thread Message Consolidator preserves user messages as conversation boundaries")
    @MainActor
    func testUserMessageBoundaries() {
        let now = Date()
        let user1 = ThreadMessage(id: "u1", role: .user, content: "Do task 1", timestamp: now)
        let agent1 = ThreadMessage(id: "a1", role: .agent, content: "Done 1", timestamp: now.addingTimeInterval(2))
        let user2 = ThreadMessage(id: "u2", role: .user, content: "Do task 2", timestamp: now.addingTimeInterval(10))
        let agent2 = ThreadMessage(id: "a2", role: .agent, content: "Done 2", timestamp: now.addingTimeInterval(12))

        let consolidated = ThreadMessageConsolidator.consolidate([user1, agent1, user2, agent2])
        #expect(consolidated.count == 4)
    }
}

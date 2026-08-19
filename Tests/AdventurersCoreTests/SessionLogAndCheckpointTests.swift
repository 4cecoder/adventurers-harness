// AdventurersCoreTests - SessionLog, CheckpointPersistence, and WorkflowRecovery Test Suite

import Testing
import Foundation
@testable import AdventurersCore

@Suite("SessionLog, Disk Checkpoints & Workflow Recovery Suite")
struct SessionLogAndCheckpointTests {

    @Test("SessionLog streams append-only JSONL events to disk and replays accurately")
    func testSessionLogAppendAndReplay() async throws {
        let threadID = UUID()
        let manager = SessionLogManager.shared

        let evt1 = SessionEvent(
            threadID: threadID,
            type: .userPrompt,
            turnIndex: 0,
            payload: ["text": "Refactor the authentication module"]
        )
        let evt2 = SessionEvent(
            threadID: threadID,
            type: .thought,
            turnIndex: 1,
            payload: ["thought": "Checking current directory contents"]
        )
        let evt3 = SessionEvent(
            threadID: threadID,
            type: .toolCall,
            turnIndex: 1,
            payload: ["tool": "bash", "command": "swift test"]
        )
        let evt4 = SessionEvent(
            threadID: threadID,
            type: .toolResult,
            turnIndex: 1,
            payload: ["tool": "bash", "output": "Test run passed."]
        )

        await manager.appendEvent(evt1)
        await manager.appendEvent(evt2)
        await manager.appendEvent(evt3)
        await manager.appendEvent(evt4)

        let replayed = await manager.replayEvents(for: threadID)
        #expect(replayed.count == 4)
        #expect(replayed[0].type == .userPrompt)
        #expect(replayed[0].payload["text"] == "Refactor the authentication module")
        #expect(replayed[2].type == .toolCall)
        #expect(replayed[2].payload["tool"] == "bash")
        #expect(replayed[3].type == .toolResult)
        #expect(replayed[3].payload["output"] == "Test run passed.")

        let markdown = await manager.exportMarkdownTranscript(for: threadID)
        #expect(markdown.contains("Refactor the authentication module"))
        #expect(markdown.contains("swift test"))

        await manager.closeLog(for: threadID)
    }

    @Test("CheckpointPersistence saves snapshots to disk and performs file rollback")
    func testCheckpointPersistenceAndRollback() async throws {
        let sessionID = UUID()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let testFileRel = "Sources/App.swift"
        let originalContent = "print(\"Original Version\")\n"
        let fullPath = (tempDir as NSString).appendingPathComponent(testFileRel)
        try FileManager.default.createDirectory(atPath: (fullPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try originalContent.write(toFile: fullPath, atomically: true, encoding: .utf8)

        let snapshot = FileSnapshot(relativePath: testFileRel, content: originalContent, fileSizeBytes: originalContent.count)
        let checkpoint = SessionCheckpoint(
            turnNumber: 1,
            summary: "Pre-refactor snapshot",
            snapshots: [snapshot],
            affectedFiles: [testFileRel]
        )

        try await CheckpointPersistence.shared.saveCheckpoint(checkpoint, sessionID: sessionID)
        let loaded = await CheckpointPersistence.shared.loadCheckpoints(for: sessionID)
        #expect(loaded.count >= 1)
        #expect(loaded.first?.summary == "Pre-refactor snapshot")

        // Mutate the file
        let corruptedContent = "BROKEN CODE ERROR"
        try corruptedContent.write(toFile: fullPath, atomically: true, encoding: .utf8)

        // Rollback
        let restored = try await CheckpointPersistence.shared.rollbackToDiskCheckpoint(checkpoint: checkpoint, workspacePath: tempDir)
        #expect(restored.contains(testFileRel))

        let restoredContent = try String(contentsOfFile: fullPath, encoding: .utf8)
        #expect(restoredContent == originalContent)

        try? FileManager.default.removeItem(atPath: tempDir)
        try? await CheckpointPersistence.shared.deleteCheckpoints(for: sessionID)
    }

    @Test("WorkflowRecoveryEngine detects interrupted sessions and rehydrates messages")
    func testWorkflowRecoveryEngine() async throws {
        let threadID = UUID()
        let manager = SessionLogManager.shared

        // Create an interrupted session (ends on a tool call without termination)
        let evt1 = SessionEvent(
            threadID: threadID,
            type: .userPrompt,
            turnIndex: 0,
            payload: ["text": "Perform database migration"]
        )
        let evt2 = SessionEvent(
            threadID: threadID,
            type: .toolCall,
            turnIndex: 1,
            payload: ["tool": "bash", "command": "run migration"]
        )

        await manager.appendEvent(evt1)
        await manager.appendEvent(evt2)

        let candidates = await WorkflowRecoveryEngine.shared.scanForRecoverableSessions()
        let found = candidates.first(where: { $0.threadID == threadID })
        #expect(found != nil)
        #expect(found?.isInterrupted == true)
        #expect(found?.recoverySuggestion.contains("Interrupted during tool execution") == true)

        let rehydrated = await WorkflowRecoveryEngine.shared.rehydrateMessages(for: threadID)
        #expect(rehydrated.count >= 1)
        #expect(rehydrated.first?.role == .user)
        #expect(rehydrated.first?.content == "Perform database migration")

        await manager.closeLog(for: threadID)
    }
}

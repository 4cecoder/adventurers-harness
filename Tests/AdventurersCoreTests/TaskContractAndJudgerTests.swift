// TaskContractAndJudgerTests.swift
// Adventurers Harness — Task Contracts, Checkpoint Rollbacks, Task Judger & Alignment Griller Tests

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Task Contract, Checkpoints, Judger & Griller Suite")
struct TaskContractAndJudgerTests {

    // MARK: - Task Contract Manager

    @Test("Task Contract phase progression and checklist tracking")
    func taskContractLifecycle() async {
        let manager = TaskContractManager()
        let sessionID = UUID()
        let contract = await manager.initializeContract(
            sessionID: sessionID,
            goal: "Refactor architecture",
            criteria: ["Clean modules"],
            steps: ["Decompose files", "Run tests", "Build DMG"]
        )

        #expect(contract.currentPhase == .planning)
        #expect(contract.steps.count == 3)
        #expect(contract.progressFraction == 0.0)

        let retrieved = await manager.getContract(for: sessionID)
        #expect(retrieved?.goal == "Refactor architecture")
        #expect(retrieved?.steps.count == 3)
    }

    @Test("Task Contract token accounting and turn limits")
    func taskContractTokenAccounting() throws {
        var contract = TaskContract(prompt: "Build feature", maxRounds: 12, maxTokens: 10_000)
        #expect(contract.maxRounds == 12)
        #expect(contract.prompt == "Build feature")

        try contract.recordTokens(prompt: 4_000, completion: 500)
        #expect(contract.consumedTokens == 4_500)
        #expect(contract.remainingTokens == 5_500)
    }

    // MARK: - Session Checkpoint Engine

    @Test("Session Checkpoint Engine creates snapshots and verifies rollback state")
    func sessionCheckpointSnapshots() async throws {
        let engine = SessionCheckpointEngine.shared
        let sessionID = UUID()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "initial content".write(to: testFile, atomically: true, encoding: .utf8)

        let checkpoint = await engine.createCheckpoint(
            sessionID: sessionID,
            turnNumber: 1,
            summary: "Before edit",
            workspacePath: tempDir.path,
            targetFiles: ["test.txt"]
        )
        #expect(checkpoint.snapshots.count == 1)

        // Modify file
        try "corrupted content".write(to: testFile, atomically: true, encoding: .utf8)

        // Rollback
        let restoredFiles = try await engine.rollback(
            sessionID: sessionID,
            checkpointID: checkpoint.id,
            workspacePath: tempDir.path
        )
        #expect(restoredFiles.contains("test.txt"))

        let restored = try String(contentsOf: testFile, encoding: .utf8)
        #expect(restored == "initial content")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Task Judger

    @Test("Task Judger classifies queries into fastDirect vs longHorizon tiers")
    func taskJudgerClassification() {
        let judger = TaskJudgerEngine.shared

        let simpleQuery = "What is the syntax for guard let in Swift?"
        let decision1 = judger.evaluate(prompt: simpleQuery)
        #expect(decision1.tier == .fastDirect)
        #expect(decision1.recommendedTurnBudget == 1)
        #expect(decision1.estimatedTokenSavingsPercent >= 80)

        let toolBatch = "Check git status and run tests on the codebase"
        let decision2 = judger.evaluate(prompt: toolBatch)
        #expect(decision2.tier == .singleToolBatch || decision2.tier == .mediumAction)

        let longHorizon = "/plan Refactor the entire networking pipeline and integrate WebSockets with rollback"
        let decision3 = judger.evaluate(prompt: longHorizon)
        #expect(decision3.tier == .longHorizon)
        #expect(decision3.shouldInitializeTaskContract == true)
    }

    // MARK: - Alignment Griller

    @Test("Alignment Griller probes ambiguous prompts and handles /grill-me")
    func alignmentGrillerProbes() {
        let griller = AlignmentGriller.shared

        let ambiguous = "fix it"
        let eval1 = griller.evaluateIntent(prompt: ambiguous)
        #expect(eval1.requiresClarification == true)
        #expect(!eval1.probes.isEmpty)

        let explicitGrill = "/grill-me I want to rewrite the auth system"
        let eval2 = griller.evaluateIntent(prompt: explicitGrill)
        #expect(eval2.requiresClarification == true)
        #expect(!eval2.probes.isEmpty)

        let clearPrompt = "In Sources/GUI/Theme.swift line 20, change adOrange opacity to 0.5"
        let eval3 = griller.evaluateIntent(prompt: clearPrompt)
        #expect(eval3.requiresClarification == false)
    }
}

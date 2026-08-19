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
        let contract = await manager.createContract(
            goal: "Refactor architecture",
            items: ["Decompose files", "Run tests", "Build DMG"]
        )

        #expect(contract.phase == .planning)
        #expect(contract.checklist.count == 3)
        #expect(contract.progressPercentage == 0)

        await manager.updatePhase(contractID: contract.id, phase: .execution)
        await manager.completeChecklistItem(contractID: contract.id, index: 0)

        let updated = await manager.contract(for: contract.id)
        #expect(updated?.phase == .execution)
        #expect(updated?.checklist[0].isCompleted == true)
        #expect(updated?.progressPercentage == 33)
    }

    @Test("Task Contract token accounting and overflow protection")
    func taskContractTokenAccounting() {
        var contract = TaskContract(prompt: "Build feature", tokenBudget: 10_000)
        #expect(contract.tokenBudget == 10_000)

        contract.recordTokensUsed(4_500)
        #expect(contract.tokensUsed == 4_500)
        #expect(contract.remainingTokens == 5_500)
        #expect(contract.isBudgetExceeded == false)

        contract.recordTokensUsed(6_000)
        #expect(contract.tokensUsed == 10_500)
        #expect(contract.isBudgetExceeded == true)
    }

    // MARK: - Session Checkpoint Engine

    @Test("Session Checkpoint Engine creates snapshots and verifies rollback state")
    func sessionCheckpointSnapshots() async {
        let engine = SessionCheckpointEngine.shared
        let sessionID = UUID()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testFile = tempDir.appendingPathComponent("test.txt")
        try? "initial content".write(to: testFile, atomically: true, encoding: .utf8)

        let checkpoint = await engine.createCheckpoint(
            sessionID: sessionID,
            turnNumber: 1,
            summary: "Before edit",
            workspacePath: tempDir.path,
            targetFiles: [testFile.path]
        )
        #expect(checkpoint != nil)

        // Modify file
        try? "corrupted content".write(to: testFile, atomically: true, encoding: .utf8)

        // Rollback
        let rolledBack = await engine.rollbackLatestCheckpoint(sessionID: sessionID)
        #expect(rolledBack == true)

        let restored = try? String(contentsOf: testFile, encoding: .utf8)
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
        #expect(decision1.maxTurns == 1)
        #expect(decision1.estimatedTokenSavingsPercent >= 80)

        let toolBatch = "Check git status and run tests on the codebase"
        let decision2 = judger.evaluate(prompt: toolBatch)
        #expect(decision2.tier == .singleToolBatch || decision2.tier == .mediumAction)

        let longHorizon = "/plan Refactor the entire networking pipeline and integrate WebSockets with rollback"
        let decision3 = judger.evaluate(prompt: longHorizon)
        #expect(decision3.tier == .longHorizon)
        #expect(decision3.requiresTaskContract == true)
    }

    // MARK: - Alignment Griller

    @Test("Alignment Griller probes ambiguous prompts and handles /grill-me")
    func alignmentGrillerProbes() {
        let griller = AlignmentGriller.shared

        let ambiguous = "fix it"
        let eval1 = griller.evaluate(prompt: ambiguous)
        #expect(eval1.isAmbiguous == true)
        #expect(!eval1.probes.isEmpty)

        let explicitGrill = "/grill-me I want to rewrite the auth system"
        let eval2 = griller.evaluate(prompt: explicitGrill)
        #expect(eval2.isAmbiguous == true)
        #expect(!eval2.probes.isEmpty)

        let clearPrompt = "In Sources/GUI/Theme.swift line 20, change adOrange opacity to 0.5"
        let eval3 = griller.evaluate(prompt: clearPrompt)
        #expect(eval3.isAmbiguous == false)
    }
}

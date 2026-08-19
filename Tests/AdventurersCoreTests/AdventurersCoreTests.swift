import Testing
import Foundation
@testable import AdventurersCore

@Suite("Adventurers Core Unit Tests")
struct AdventurersCoreTests {
    @Test("Task Contract budget counting")
    func taskContractBudget() throws {
        var contract = TaskContract(prompt: "test", maxRounds: 2)
        #expect(contract.remainingRounds == 2)
        _ = try contract.bumpRound()
        #expect(contract.remainingRounds == 1)
        _ = try contract.bumpRound()
        #expect(contract.remainingRounds == 0)
        #expect(throws: ContractError.self) {
            try contract.bumpRound()
        }
    }

    @Test("State Engine valid and invalid transitions")
    func stateEngineTransitions() async throws {
        let engine = StateEngine()
        #expect(await engine.current() == .idle)
        try await engine.transition(to: .taskingested)
        #expect(await engine.current() == .taskingested)
        await #expect(throws: StateError.self) {
            try await engine.transition(to: .verified)
        }
    }

    @Test("Fail Chain escalation and reset")
    func failChain() async throws {
        let chain = FailChain()
        #expect(await chain.count(for: "syntax") == 0)
        await chain.record(gate: "syntax")
        #expect(await chain.count(for: "syntax") == 1)
        await chain.record(gate: "syntax")
        #expect(await chain.count(for: "syntax") == 2)
        await chain.reset(gate: "syntax")
        #expect(await chain.count(for: "syntax") == 0)
    }

    @Test("Repeat Gate duplicate output detection")
    func repeatGate() async throws {
        let gate = RepeatGate()
        let contract = TaskContract(prompt: "test", maxRounds: 5)
        let output1 = AgentOutput(content: "hello", toolCalls: [], turnIndex: 0, timestamp: Date())
        let context1 = GateContext(taskID: "1", contract: contract, previousOutputs: [output1])

        let result1 = await gate.evaluate(output1, context: context1)
        #expect(result1.passed == true)

        let output2 = AgentOutput(content: "hello", toolCalls: [], turnIndex: 1, timestamp: Date())
        let context2 = GateContext(taskID: "1", contract: contract, previousOutputs: [output1, output2])
        let result2 = await gate.evaluate(output2, context: context2)
        #expect(result2.passed == false)
    }

    @Test("Syntax Gate brace balancing")
    func syntaxGate() async throws {
        let gate = SyntaxGate()
        let contract = TaskContract(prompt: "test", maxRounds: 5)
        let context = GateContext(taskID: "1", contract: contract, previousOutputs: [])

        let balanced = AgentOutput(content: "func foo() { return 1 }", toolCalls: [], turnIndex: 0, timestamp: Date())
        let result1 = await gate.evaluate(balanced, context: context)
        #expect(result1.passed == true)

        let unbalanced = AgentOutput(content: "func foo() { return 1", toolCalls: [], turnIndex: 1, timestamp: Date())
        let result2 = await gate.evaluate(unbalanced, context: context)
        #expect(result2.passed == false)
    }

    @Test("Darwin Seatbelt Sandbox path access validation")
    func sandboxValidation() async throws {
        let sandbox = DarwinSandbox.shared
        let workspace = URL(fileURLWithPath: "/Users/fource/workspace/test")

        let modeReadOnly = SandboxMode.readOnly
        #expect(await sandbox.validatePathAccess(targetPath: "/Users/fource/workspace/test/file.swift", mode: modeReadOnly) == false)

        let modeWorkspace = SandboxMode.workspaceWrite(workspaceRoot: workspace)
        #expect(await sandbox.validatePathAccess(targetPath: "/Users/fource/workspace/test/file.swift", mode: modeWorkspace) == true)
        #expect(await sandbox.validatePathAccess(targetPath: "/etc/passwd", mode: modeWorkspace) == false)
        #expect(await sandbox.validatePathAccess(targetPath: "/Users/fource/.ssh/id_rsa", mode: modeWorkspace) == false)
    }

    @Test("Diff Engine preflight check and atomic patch application")
    func diffEnginePreflightAndApply() throws {
        let engine = DiffEngine.shared
        let original = "line 1\nline 2\nline 3"
        let rawDiff = """
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,3 @@
         line 1
        -line 2
        +line 2 modified
         line 3
        """

        let patches = engine.parseUnifiedDiff(rawDiff)
        #expect(patches.count == 1)
        #expect(patches[0].hunks.count == 1)

        let check = engine.preflight(originalContent: original, hunks: patches[0].hunks)
        if case .ready = check {
            let applied = try engine.apply(originalContent: original, hunks: patches[0].hunks)
            #expect(applied == "line 1\nline 2 modified\nline 3")
        } else {
            #expect(Bool(false), "Preflight should succeed")
        }
    }

    @Test("Hermes Trajectory Compression Anchor Preservation")
    func trajectoryCompressorAnchor() async throws {
        let config = TrajectoryCompressionConfig(
            targetMaxTokens: 200,
            protectedHeadTurns: 2,
            protectedTailTurns: 2
        )
        let compressor = TrajectoryCompressor(config: config)

        let turns: [TrajectoryTurn] = [
            TrajectoryTurn(role: "system", content: "You are Adventurers coding harness.", tokenCountEstimate: 50),
            TrajectoryTurn(role: "user", content: "Implement pure Swift sandboxing.", tokenCountEstimate: 50),
            // Middle turns (over budget)
            TrajectoryTurn(role: "assistant", content: "Plan: check Darwin headers.", tokenCountEstimate: 60),
            TrajectoryTurn(role: "tool", content: "Tool output: Darwin/sandbox.h found with symbols.", tokenCountEstimate: 120),
            TrajectoryTurn(role: "assistant", content: "Plan: compile Swift 6 module.", tokenCountEstimate: 60),
            // Tail turns (protected)
            TrajectoryTurn(role: "assistant", content: "Finished implementation.", tokenCountEstimate: 40),
            TrajectoryTurn(role: "user", content: "Verify gates passed.", tokenCountEstimate: 20),
        ]

        #expect(await compressor.requiresCompression(turns) == true)
        let compressed = await compressor.compressTrajectory(turns)

        // Head (2) + Summary (1) + Tail (2) = 5 turns
        #expect(compressed.count == 5)
        #expect(compressed[0].role == "system")
        #expect(compressed[1].role == "user")
        #expect(compressed[2].role == "user")
        #expect(compressed[2].content.contains("[Summary of 3 intermediate execution turns]"))
        #expect(compressed[3].content == "Finished implementation.")
        #expect(compressed[4].content == "Verify gates passed.")
    }

    @Test("Memory Gate and Objective Gate validation")
    func memoryAndObjectiveGates() async throws {
        let memoryGate = MemoryGate()
        let objectiveGate = ObjectiveGate()

        let contract = TaskContract(prompt: "Implement pure Swift sandboxing with Darwin Seatbelt", maxRounds: 5)
        let relevantOutput = AgentOutput(
            content: "Implemented Darwin Seatbelt pure Swift sandbox profile generation.",
            toolCalls: [],
            turnIndex: 0,
            timestamp: Date()
        )
        let context = GateContext(taskID: "test-gates", contract: contract, previousOutputs: [])

        let memResult = await memoryGate.evaluate(relevantOutput, context: context)
        #expect(memResult.passed == true)

        let objResult = await objectiveGate.evaluate(relevantOutput, context: context)
        #expect(objResult.passed == true)
    }

    @Test("Diff Gate destructive command detection")
    func diffGateDestructiveCommands() async throws {
        let diffGate = DiffGate()
        let contract = TaskContract(prompt: "test", maxRounds: 5)
        let context = GateContext(taskID: "1", contract: contract, previousOutputs: [])

        // Test destructive command detection
        let destructiveOutput = AgentOutput(
            content: "Running command: rm -rf /important/directory",
            toolCalls: [],
            turnIndex: 0,
            timestamp: Date()
        )
        let destructResult = await diffGate.evaluate(destructiveOutput, context: context)
        #expect(destructResult.passed == false)
        #expect(destructResult.error?.contains("Destructive command") == true)

        // Test safe output
        let safeOutput = AgentOutput(
            content: "Created new file with improvements",
            toolCalls: [],
            turnIndex: 0,
            timestamp: Date()
        )
        let safeResult = await diffGate.evaluate(safeOutput, context: context)
        #expect(safeResult.passed == true)
    }

    @Test("Diff Gate sensitive file access detection")
    func diffGateSensitiveFiles() async throws {
        let diffGate = DiffGate()
        let contract = TaskContract(prompt: "test", maxRounds: 5)
        let context = GateContext(taskID: "1", contract: contract, previousOutputs: [])

        // Test sensitive file access
        let sensitiveOutput = AgentOutput(
            content: "Reading from ~/.ssh/id_rsa",
            toolCalls: [],
            turnIndex: 0,
            timestamp: Date()
        )
        let sensitiveResult = await diffGate.evaluate(sensitiveOutput, context: context)
        #expect(sensitiveResult.passed == false)
        #expect(sensitiveResult.error?.contains("Sensitive file") == true)
    }

    @Test("Model Pricing Registry and Spec calculations")
    func modelPricingAndSpec() {
        let registry = ModelPricingRegistry.shared
        
        let claude = registry.spec(for: "claude-3-7-sonnet")
        #expect(claude.contextLimit == 200_000)
        #expect(claude.family == "Claude Sonnet")
        let claudeCost = claude.calculateCost(promptTokens: 10_000, completionTokens: 2_000, reasoningTokens: 500)
        // (10k / 1M)*3 + (1.5k / 1M)*15 + (0.5k / 1M)*15 = 0.030 + 0.0225 + 0.0075 = 0.060
        #expect(abs(claudeCost - 0.06) < 0.0001)

        let gpt4oMini = registry.spec(for: "gpt-4o-mini")
        #expect(gpt4oMini.contextLimit == 128_000)
        #expect(gpt4oMini.family == "GPT-4o mini")

        let deepseekR1 = registry.spec(for: "deepseek-r1")
        #expect(deepseekR1.family == "DeepSeek R1")

        let minimax = registry.spec(for: "minimax-m3")
        #expect(minimax.contextLimit == 1_000_000)
    }

    @Test("Turn Metrics calculation and formatting")
    func turnMetricsFormatting() {
        let metrics = TurnMetrics(
            turnNumber: 1,
            model: "claude-3-7-sonnet",
            provider: "Anthropic",
            promptTokens: 1200,
            completionTokens: 600,
            reasoningTokens: 200,
            ttftMs: 350.0,
            durationSeconds: 2.5,
            tps: 240.0,
            peakTps: 280.0,
            estimatedCostUSD: 0.0126,
            toolCallsCount: 2,
            gatesPassedCount: 6
        )

        #expect(metrics.formattedTPS == "240.0 tok/s")
        #expect(metrics.formattedPeakTPS == "280.0 tok/s")
        #expect(metrics.formattedTTFT == "350ms TTFT")
        #expect(metrics.formattedDuration == "2.50s")
        #expect(metrics.formattedCost == "$0.013")
        #expect(metrics.totalTokens == 1800)
    }

    @Test("Meta Harness discovery, types, and profile configuration")
    func metaHarnessProfilesAndDiscovery() {
        let registry = MetaHarnessRegistry.shared
        let profiles = registry.discoverProfiles()

        #expect(!profiles.isEmpty)
        #expect(profiles.count >= MetaHarnessType.allCases.count)

        // Verify Codex profile
        let codex = profiles.first(where: { $0.type == .codex })
        #expect(codex != nil)
        #expect(codex?.type.defaultBinaryName == "codex")
        #expect(codex?.type.defaultEnvKeyName == "CODEX_API_KEY")

        // Verify Hermes profile
        let hermes = profiles.first(where: { $0.type == .hermes })
        #expect(hermes != nil)
        #expect(hermes?.type.defaultBinaryName == "hermes")
        #expect(hermes?.type.defaultEnvKeyName == "HERMES_API_KEY")

        // Verify ExecutionMode
        #expect(ExecutionMode.codingPlan.shortLabel == "Coding Plan")
        #expect(ExecutionMode.metaHarness.shortLabel == "Meta Harness")
    }
}




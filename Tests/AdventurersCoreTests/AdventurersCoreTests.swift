import Testing
import Foundation
@testable import AdventurersCore

@Suite("Adventurers Core Unit Tests & Microtest Suite")
struct AdventurersCoreTests {

    // MARK: - 1. Task Contract Microtests

    @Test("Task Contract initial values and budget limits")
    func taskContractInitialValues() {
        let contract = TaskContract(prompt: "Build swift gate", maxRounds: 10, maxTokens: 50_000)
        #expect(contract.prompt == "Build swift gate")
        #expect(contract.maxRounds == 10)
        #expect(contract.remainingRounds == 10)
        #expect(contract.maxTokens == 50_000)
        #expect(contract.consumedTokens == 0)
    }

    @Test("Task Contract round budget decrement and exhaustion")
    func taskContractBudgetExhaustion() throws {
        var contract = TaskContract(prompt: "test", maxRounds: 3)
        #expect(contract.remainingRounds == 3)
        _ = try contract.bumpRound()
        #expect(contract.remainingRounds == 2)
        _ = try contract.bumpRound()
        #expect(contract.remainingRounds == 1)
        _ = try contract.bumpRound()
        #expect(contract.remainingRounds == 0)
        #expect(throws: ContractError.self) {
            try contract.bumpRound()
        }
    }

    @Test("Task Contract token accounting and overflow protection")
    func taskContractTokenAccounting() throws {
        var contract = TaskContract(prompt: "test", maxRounds: 5, maxTokens: 1000)
        try contract.recordTokens(prompt: 400, completion: 200)
        #expect(contract.consumedTokens == 600)
        #expect(contract.remainingTokens == 400)

        #expect(throws: ContractError.self) {
            try contract.recordTokens(prompt: 300, completion: 200) // 600 + 500 = 1100 > 1000
        }
    }

    // MARK: - 2. State Engine Finite State Machine Microtests

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
    func stateEngineIllegalTransitions() async throws {
        let engine = StateEngine()
        #expect(await engine.current() == .idle)

        // Cannot skip directly from idle to verified
        do {
            try await engine.transition(to: .verified)
            #expect(Bool(false), "Should have thrown StateError")
        } catch is StateError {
            #expect(Bool(true))
        }

        // Cannot skip directly from idle to executingTest
        do {
            try await engine.transition(to: .executingTest)
            #expect(Bool(false), "Should have thrown StateError")
        } catch is StateError {
            #expect(Bool(true))
        }
    }

    @Test("State Engine gating rejection and re-proposing loop")
    func stateEngineRejectionLoop() async throws {
        let engine = StateEngine()
        try await engine.transition(to: .taskingested)
        try await engine.transition(to: .proposing)
        try await engine.transition(to: .validatingSyntax)

        // Syntax fails -> retrying
        try await engine.transition(to: .retrying)
        #expect(await engine.current() == .retrying)

        // Loop back to proposing to self-correct
        try await engine.transition(to: .proposing)
        #expect(await engine.current() == .proposing)
    }

    // MARK: - 3. FailChain Escalation Engine Microtests

    @Test("Fail Chain multi-tier escalation and per-gate isolation")
    func failChainMultiGateEscalation() async throws {
        let chain = FailChain()
        #expect(await chain.count(for: "syntax") == 0)
        #expect(await chain.count(for: "compilation") == 0)

        await chain.record(gate: "syntax")
        #expect(await chain.count(for: "syntax") == 1)
        #expect(await chain.count(for: "compilation") == 0)

        await chain.record(gate: "syntax")
        #expect(await chain.count(for: "syntax") == 2)

        await chain.record(gate: "compilation")
        #expect(await chain.count(for: "compilation") == 1)
        #expect(await chain.count(for: "syntax") == 2)

        // Reset only syntax gate
        await chain.reset(gate: "syntax")
        #expect(await chain.count(for: "syntax") == 0)
        #expect(await chain.count(for: "compilation") == 1)
    }

    @Test("Fail Chain escalation feedback message generation")
    func failChainMessageFormatting() async throws {
        let chain = FailChain()
        await chain.record(gate: "diff")
        let failure1 = GateResult(passed: false, gateName: "diff", error: "Sensitive file touched")
        let capsule1 = await chain.mitigate(failures: [failure1])
        #expect(capsule1.contains("Gate 'diff' failed"))

        await chain.record(gate: "diff")
        let capsule2 = await chain.mitigate(failures: [failure1])
        #expect(capsule2.contains("AGAIN"))

        await chain.record(gate: "diff")
        let capsule3 = await chain.mitigate(failures: [failure1])
        #expect(capsule3.contains("CRITICAL"))
    }

    // MARK: - 4. 6-Gate Certification Pipeline Microtests

    @Test("Syntax Gate handles nested brackets, strings, and unbalanced closures")
    func syntaxGateBoundaryCases() async throws {
        let gate = SyntaxGate()
        let contract = TaskContract(prompt: "test", maxRounds: 5)
        let context = GateContext(taskID: "1", contract: contract, previousOutputs: [])

        // Balanced with nested brackets
        let nestedBalanced = AgentOutput(
            content: "func test() { let arr = [1, 2, (3 + 4)] }",
            toolCalls: [],
            turnIndex: 0,
            timestamp: Date()
        )
        let r1 = await gate.evaluate(nestedBalanced, context: context)
        #expect(r1.passed == true)

        // Unbalanced square bracket
        let unbalancedSquare = AgentOutput(
            content: "let arr = [1, 2, 3",
            toolCalls: [],
            turnIndex: 1,
            timestamp: Date()
        )
        let r2 = await gate.evaluate(unbalancedSquare, context: context)
        #expect(r2.passed == false)

        // Unbalanced parenthesis
        let unbalancedParen = AgentOutput(
            content: "print((x + 1)",
            toolCalls: [],
            turnIndex: 2,
            timestamp: Date()
        )
        let r3 = await gate.evaluate(unbalancedParen, context: context)
        #expect(r3.passed == false)
    }

    @Test("Repeat Gate detects loop cycles and ignores non-duplicate turns")
    func repeatGateCycleDetection() async throws {
        let gate = RepeatGate()
        let contract = TaskContract(prompt: "test", maxRounds: 5)

        let out1 = AgentOutput(content: "step 1: inspect files", toolCalls: [], turnIndex: 0, timestamp: Date())
        let out2 = AgentOutput(content: "step 2: compile sources", toolCalls: [], turnIndex: 1, timestamp: Date())
        let out3 = AgentOutput(content: "step 1: inspect files", toolCalls: [], turnIndex: 2, timestamp: Date())

        let ctx1 = GateContext(taskID: "1", contract: contract, previousOutputs: [out1])
        let r1 = await gate.evaluate(out2, context: ctx1)
        #expect(r1.passed == true)

        let ctx2 = GateContext(taskID: "1", contract: contract, previousOutputs: [out1, out2, out3])
        let r2 = await gate.evaluate(out3, context: ctx2)
        #expect(r2.passed == false)
    }

    @Test("Diff Gate identifies high-risk commands and protected files")
    func diffGateRiskDetection() async throws {
        let diffGate = DiffGate()
        let contract = TaskContract(prompt: "test", maxRounds: 5)
        let context = GateContext(taskID: "1", contract: contract, previousOutputs: [])

        // 1. Force push detection
        let forcePush = AgentOutput(content: "git push --force origin master", toolCalls: [], turnIndex: 0, timestamp: Date())
        let r1 = await diffGate.evaluate(forcePush, context: context)
        #expect(r1.passed == false)

        // 2. Sudo command detection
        let sudoCmd = AgentOutput(content: "sudo chmod -R 777 /", toolCalls: [], turnIndex: 1, timestamp: Date())
        let r2 = await diffGate.evaluate(sudoCmd, context: context)
        #expect(r2.passed == false)

        // 3. Sensitive .env modification
        let envTouch = AgentOutput(content: "Writing secrets to .env.production", toolCalls: [], turnIndex: 2, timestamp: Date())
        let r3 = await diffGate.evaluate(envTouch, context: context)
        #expect(r3.passed == false)

        // 4. Safe command
        let safeCmd = AgentOutput(content: "swift test --filter Core", toolCalls: [], turnIndex: 3, timestamp: Date())
        let r4 = await diffGate.evaluate(safeCmd, context: context)
        #expect(r4.passed == true)
    }

    @Test("Memory Gate bounds execution memory via POSIX rusage")
    func memoryGateEvaluation() async throws {
        let memoryGate = MemoryGate(maxResidentBytes: 500 * 1024 * 1024) // 500MB
        let contract = TaskContract(prompt: "test", maxRounds: 5)
        let context = GateContext(taskID: "1", contract: contract, previousOutputs: [])
        let output = AgentOutput(content: "Memory check test", toolCalls: [], turnIndex: 0, timestamp: Date())

        let result = await memoryGate.evaluate(output, context: context)
        #expect(result.passed == true)
        #expect(result.output.contains("Memory within safe bounds") == true)
    }

    @Test("Objective Gate verifies task keyword completion")
    func objectiveGateEvaluation() async throws {
        let objectiveGate = ObjectiveGate()
        let contract = TaskContract(prompt: "Implement Darwin Seatbelt pure Swift sandbox", maxRounds: 5)
        let context = GateContext(taskID: "1", contract: contract, previousOutputs: [])

        let relevantOutput = AgentOutput(
            content: "Implemented Darwin Seatbelt pure Swift sandbox profile generation.",
            toolCalls: [],
            turnIndex: 0,
            timestamp: Date()
        )
        let r1 = await objectiveGate.evaluate(relevantOutput, context: context)
        #expect(r1.passed == true)
    }

    // MARK: - 5. Darwin Sandbox Microtests

    @Test("Darwin Sandbox profile policy generation and path checks")
    func darwinSandboxPathAccess() async throws {
        let sandbox = DarwinSandbox.shared
        let workspace = URL(fileURLWithPath: "/Users/fource/workspace/test")

        let modeReadOnly = SandboxMode.readOnly
        #expect(await sandbox.validatePathAccess(targetPath: "/Users/fource/workspace/test/file.swift", mode: modeReadOnly) == false)

        let modeWorkspace = SandboxMode.workspaceWrite(workspaceRoot: workspace)
        #expect(await sandbox.validatePathAccess(targetPath: "/Users/fource/workspace/test/Sources/App.swift", mode: modeWorkspace) == true)
        #expect(await sandbox.validatePathAccess(targetPath: "/etc/shadow", mode: modeWorkspace) == false)
        #expect(await sandbox.validatePathAccess(targetPath: "/Users/fource/.ssh/known_hosts", mode: modeWorkspace) == false)
        #expect(await sandbox.validatePathAccess(targetPath: "/private/var/root", mode: modeWorkspace) == false)
    }

    // MARK: - 6. Diff Engine Microtests

    @Test("Diff Engine single and multi-hunk patch application")
    func diffEngineMultiHunk() throws {
        let engine = DiffEngine.shared
        let original = "line 1\nline 2\nline 3\nline 4\nline 5"
        let rawDiff = [
            "--- a/file.txt",
            "+++ b/file.txt",
            "@@ -1,5 +1,5 @@",
            " line 1",
            "-line 2",
            "+line 2 patched",
            " line 3",
            "-line 4",
            "+line 4 patched",
            " line 5"
        ].joined(separator: "\n")

        let patches = engine.parseUnifiedDiff(rawDiff)
        #expect(patches.count == 1)

        let check = engine.preflight(originalContent: original, hunks: patches[0].hunks)
        if case .ready = check {
            let applied = try engine.apply(originalContent: original, hunks: patches[0].hunks)
            #expect(applied == "line 1\nline 2 patched\nline 3\nline 4 patched\nline 5")
        } else {
            #expect(Bool(false), "Preflight should succeed on matching context")
        }
    }

    @Test("Diff Engine rejects patches with corrupted context")
    func diffEngineCorruptedContext() {
        let engine = DiffEngine.shared
        let original = "completely different content"
        let rawDiff = [
            "--- a/file.txt",
            "+++ b/file.txt",
            "@@ -1,3 +1,3 @@",
            " line 1",
            "-line 2",
            "+line 2 modified",
            " line 3"
        ].joined(separator: "\n")

        let patches = engine.parseUnifiedDiff(rawDiff)
        #expect(patches.count == 1)

        let check = engine.preflight(originalContent: original, hunks: patches[0].hunks)
        if case .conflict = check {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Preflight should detect context mismatch")
        }
    }

    // MARK: - 7. Trajectory Compressor Microtests

    @Test("Trajectory Compressor preserves head and tail anchors")
    func trajectoryCompressorAnchorPreservation() async throws {
        let config = TrajectoryCompressionConfig(
            targetMaxTokens: 200,
            protectedHeadTurns: 2,
            protectedTailTurns: 2
        )
        let compressor = TrajectoryCompressor(config: config)

        let turns: [TrajectoryTurn] = [
            TrajectoryTurn(role: "system", content: "System prompt instructions.", tokenCountEstimate: 50),
            TrajectoryTurn(role: "user", content: "Initial user goal.", tokenCountEstimate: 50),
            TrajectoryTurn(role: "assistant", content: "Intermediate turn A.", tokenCountEstimate: 80),
            TrajectoryTurn(role: "tool", content: "Intermediate turn B.", tokenCountEstimate: 90),
            TrajectoryTurn(role: "assistant", content: "Intermediate turn C.", tokenCountEstimate: 80),
            TrajectoryTurn(role: "assistant", content: "Final conclusion.", tokenCountEstimate: 30),
            TrajectoryTurn(role: "user", content: "Final validation.", tokenCountEstimate: 20),
        ]

        #expect(await compressor.requiresCompression(turns) == true)
        let compressed = await compressor.compressTrajectory(turns)

        #expect(compressed.count == 5)
        #expect(compressed[0].content == "System prompt instructions.")
        #expect(compressed[1].content == "Initial user goal.")
        #expect(compressed[2].role == "user")
        #expect(compressed[2].content.contains("[Summary of 3 intermediate execution turns]"))
        #expect(compressed[3].content == "Final conclusion.")
        #expect(compressed[4].content == "Final validation.")
    }

    // MARK: - 8. Model Pricing & Telemetry Microtests

    @Test("Model Pricing Registry calculations across multiple model tiers")
    func modelPricingMultiTier() {
        let registry = ModelPricingRegistry.shared

        // Claude 3.7 Sonnet ($3 / $15 per 1M)
        let claude = registry.spec(for: "claude-3-7-sonnet")
        let claudeCost = claude.calculateCost(promptTokens: 1_000_000, completionTokens: 1_000_000, reasoningTokens: 0)
        #expect(abs(claudeCost - 18.0) < 0.001)

        // DeepSeek R1 ($0.55 / $2.19 per 1M)
        let deepseek = registry.spec(for: "deepseek-r1")
        #expect(deepseek.family == "DeepSeek R1")
        let deepseekCost = deepseek.calculateCost(promptTokens: 1_000_000, completionTokens: 1_000_000, reasoningTokens: 0)
        #expect(abs(deepseekCost - (0.55 + 2.19)) < 0.001)

        // MiniMax M3 (1M context limit)
        let minimax = registry.spec(for: "minimax-m3")
        #expect(minimax.contextLimit == 1_000_000)
    }

    @Test("Turn Metrics formatting and token velocity accounting")
    func turnMetricsAccounting() {
        let metrics = TurnMetrics(
            turnNumber: 1,
            model: "claude-3-7-sonnet",
            provider: "Anthropic",
            promptTokens: 1000,
            completionTokens: 500,
            reasoningTokens: 100,
            ttftMs: 280.0,
            durationSeconds: 2.0,
            tps: 250.0,
            peakTps: 310.0,
            estimatedCostUSD: 0.0105,
            toolCallsCount: 1,
            gatesPassedCount: 6
        )

        #expect(metrics.totalTokens == 1500)
        #expect(metrics.formattedTPS == "250.0 tok/s")
        #expect(metrics.formattedPeakTPS == "310.0 tok/s")
        #expect(metrics.formattedTTFT == "280ms TTFT")
        #expect(metrics.formattedDuration == "2.00s")
    }

    // MARK: - 9. Meta-Harness Registry Microtests

    @Test("Meta Harness registry discovered profiles and CLI mappings")
    func metaHarnessRegistryDiscovery() {
        let registry = MetaHarnessRegistry.shared
        let profiles = registry.discoverProfiles()

        #expect(profiles.count >= 8)

        // Verify Antigravity CLI (agy) profile
        let agy = profiles.first(where: { $0.type == .antigravity })
        #expect(agy != nil)
        #expect(agy?.type.defaultBinaryName == "agy")
        #expect(agy?.type.defaultEnvKeyName == "GEMINI_API_KEY")

        // Verify Claude Code CLI (claude) profile
        let claude = profiles.first(where: { $0.type == .claudeCode })
        #expect(claude != nil)
        #expect(claude?.type.defaultBinaryName == "claude")
        #expect(claude?.type.defaultEnvKeyName == "ANTHROPIC_API_KEY")

        // Verify standard profiles
        let codex = profiles.first(where: { $0.type == .codex })
        #expect(codex?.type.defaultBinaryName == "codex")
        #expect(codex?.type.defaultEnvKeyName == "CODEX_API_KEY")

        let hermes = profiles.first(where: { $0.type == .hermes })
        #expect(hermes?.type.defaultBinaryName == "hermes")
        #expect(hermes?.type.defaultEnvKeyName == "HERMES_API_KEY")

        let opencode = profiles.first(where: { $0.type == .opencode })
        #expect(opencode?.type.defaultBinaryName == "opencode")

        let dsh = profiles.first(where: { $0.type == .deepseekHarness })
        #expect(dsh?.type.defaultBinaryName == "dsh")
    }

    // MARK: - 10. Active Process Registry Microtests

    @Test("Active Process Registry tracks and unregisters processes")
    func activeProcessRegistryTracking() {
        let registry = ActiveProcessRegistry.shared
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/echo")
        proc.arguments = ["harness test"]

        try? proc.run()
        let pid = proc.processIdentifier
        #expect(pid > 0)

        registry.register(process: proc)
        registry.unregister(process: proc)
        registry.unregister(pid: pid)
        proc.waitUntilExit()
    }

    @Test("Meta Harness Auth Mode classification")
    func metaHarnessAuthModes() {
        let nativeMode = MetaHarnessAuthMode.nativeSubscription
        let keyMode = MetaHarnessAuthMode.injectedApiKey
        let hybridMode = MetaHarnessAuthMode.hybrid

        #expect(nativeMode.rawValue.contains("Subscription"))
        #expect(keyMode.rawValue.contains("Injected"))
        #expect(hybridMode.rawValue.contains("Hybrid"))
        #expect(MetaHarnessAuthMode.allCases.count == 3)
    }

    @Test("WorkspaceConfig resolves valid non-root directory")
    func workspaceConfigResolution() {
        let path = WorkspaceConfig.defaultWorkspacePath
        #expect(path != "/")
        #expect(path.hasPrefix("/Users/"))
        #expect(FileManager.default.fileExists(atPath: path))
    }
}

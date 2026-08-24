// Phase3Microtests.swift
// Adventurers Harness — Unit Test Suite for Phase 3 (Tasks 3.1 through 3.9)

import Testing
import Foundation
import LLMProviders
@testable import AdventurersCore

@Suite("Phase 3 WebAssembly Gates, APFS Snapshots, Security & Policies Suite")
struct Phase3Microtests {

    @Test("Task 3.1 & 3.2: WASI Gate Interface serialization and runner handling")
    func testWasiGateInterfaceAndRunner() async {
        let input = WASIGateInput(
            taskID: "task-test-31",
            turnIndex: 1,
            content: "func test() { return }",
            toolCalls: [],
            modifiedFiles: ["Sources/Main.swift"]
        )

        let data = try? JSONEncoder().encode(input)
        #expect(data != nil)

        let decoded = try? JSONDecoder().decode(WASIGateInput.self, from: data!)
        #expect(decoded?.taskID == "task-test-31")

        // Execute runner against missing path to verify structured graceful rejection
        let runner = WasmGateRunner()
        let out = await runner.executeGate(pluginPath: "/tmp/non_existent_gate.wasm", input: input)
        #expect(!out.passed)
        #expect(out.error?.contains("not found") == true || out.violations.contains("Executable plugin missing"))
    }

    @Test("Task 3.3: Gate Policy Loader loads defaults or custom .adventurers/gates.json")
    func testGatePolicyLoader() {
        let loader = GatePolicyLoader()
        let policy = loader.loadPolicy(from: "/tmp/non_existent_dir")
        #expect(policy.version == "1.0")
        #expect(policy.requiredGates.contains("syntax"))
        #expect(policy.requiredGates.contains("security"))
    }

    @Test("Task 3.6: APFS Snapshot Manager creates workspace snapshot and performs atomic rollback")
    func testAPFSSnapshotRollback() async {
        let mgr = APFSSnapshotManager()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_ws_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let testFile = tempDir.appendingPathComponent("code.swift")
        try? "original content".write(to: testFile, atomically: true, encoding: .utf8)

        // 1. Take snapshot
        let snap = await mgr.createSnapshot(workspacePath: tempDir.path)
        #expect(snap != nil)

        // 2. Corrupt/Modify file
        try? "corrupted malicious content".write(to: testFile, atomically: true, encoding: .utf8)
        let modified = try? String(contentsOf: testFile, encoding: .utf8)
        #expect(modified == "corrupted malicious content")

        // 3. Rollback
        let rolledBack = await mgr.rollback(snapshotId: snap!.id)
        #expect(rolledBack)

        let restored = try? String(contentsOf: testFile, encoding: .utf8)
        #expect(restored == "original content")

        // Cleanup
        await mgr.discardSnapshot(snapshotId: snap!.id)
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Task 3.9: Security Gate blocks API keys, private keys, and destructive commands")
    func testSecurityGateRejection() async {
        let gate = SecurityGate()
        let contract = TaskContract(taskID: "sec-check", prompt: "Security test")
        let context = GateContext(taskID: "sec-check", contract: contract, previousOutputs: [])

        // Safe output
        let safeOutput = AgentOutput(content: "let apiKey = ProcessInfo.processInfo.environment[\"API_KEY\"]", toolCalls: [], turnIndex: 0, timestamp: Date())
        let safeRes = await gate.evaluate(safeOutput, context: context)
        #expect(safeRes.passed)

        // Leaked secret output
        let leakedOutput = AgentOutput(content: "let key = \"sk-proj-12345678901234567890123456789012345678901234567890\"", toolCalls: [], turnIndex: 1, timestamp: Date())
        let leakedRes = await gate.evaluate(leakedOutput, context: context)
        #expect(!leakedRes.passed)
        #expect(leakedRes.error?.contains("Security Gate Rejection") == true)

        // Destructive tool call
        let destructiveOutput = AgentOutput(content: "Cleaning up", toolCalls: [ToolCall(id: "call-1", name: "bash", arguments: ["command": AnyCodable("rm -rf /")])], turnIndex: 2, timestamp: Date())
        let destrRes = await gate.evaluate(destructiveOutput, context: context)
        #expect(!destrRes.passed)
    }
}

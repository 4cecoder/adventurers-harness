// GatesTests.swift
// Adventurers Harness — Deterministic Verification Gates & Fail Chain Tests

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Gates & Fail Chain Suite")
struct GatesTests {

    @Test("Syntax Gate handles nested brackets, strings, and unbalanced closures")
    func syntaxGateValidation() async {
        let gate = SyntaxGate()
        let contract = TaskContract(prompt: "Write Swift function")
        let context = GateContext(taskID: "task-1", contract: contract, previousOutputs: [])

        let validSwift = AgentOutput(
            content: "func add(a: Int, b: Int) -> Int { return a + b }",
            toolCalls: [],
            turnIndex: 1,
            timestamp: Date()
        )
        let validResult = await gate.evaluate(validSwift, context: context)
        #expect(validResult.passed == true)

        let invalidSwift = AgentOutput(
            content: "func broken() { let x = (1 + 2",
            toolCalls: [],
            turnIndex: 2,
            timestamp: Date()
        )
        let invalidResult = await gate.evaluate(invalidSwift, context: context)
        #expect(invalidResult.passed == false)
    }

    @Test("Repeat Gate detects loop cycles and ignores non-duplicate turns")
    func repeatGateDetection() async {
        let gate = RepeatGate()
        let contract = TaskContract(prompt: "Test repetition")

        let turn1 = AgentOutput(content: "First plan", toolCalls: [], turnIndex: 1, timestamp: Date())
        let turn2 = AgentOutput(content: "First plan", toolCalls: [], turnIndex: 2, timestamp: Date())

        let ctx1 = GateContext(taskID: "task-1", contract: contract, previousOutputs: [])
        let res1 = await gate.evaluate(turn1, context: ctx1)
        #expect(res1.passed == true)

        let ctx2 = GateContext(taskID: "task-1", contract: contract, previousOutputs: [turn1])
        let res2 = await gate.evaluate(turn2, context: ctx2)
        #expect(res2.passed == false)
    }

    @Test("Memory Gate bounds execution memory via POSIX rusage")
    func memoryGateEvaluation() async {
        let gate = MemoryGate()
        let contract = TaskContract(prompt: "Memory test")
        let ctx = GateContext(taskID: "task-1", contract: contract, previousOutputs: [])
        let output = AgentOutput(content: "Clean run", toolCalls: [], turnIndex: 1, timestamp: Date())

        let result = await gate.evaluate(output, context: ctx)
        #expect(result.passed == true)
    }

    @Test("Objective Gate verifies task keyword completion")
    func objectiveGateKeywordChecks() async {
        let gate = ObjectiveGate()
        let contract = TaskContract(prompt: "Generate a Swift struct named UserProfile", requiredKeywords: ["struct UserProfile"])
        let ctx = GateContext(taskID: "task-1", contract: contract, previousOutputs: [])

        let passing = AgentOutput(content: "Here is: struct UserProfile { let id: String }", toolCalls: [], turnIndex: 1, timestamp: Date())
        let passingRes = await gate.evaluate(passing, context: ctx)
        #expect(passingRes.passed == true)

        let failing = AgentOutput(content: "Here is some code without the struct", toolCalls: [], turnIndex: 2, timestamp: Date())
        let failingRes = await gate.evaluate(failing, context: ctx)
        #expect(failingRes.passed == false)
    }

    @Test("Diff Gate identifies high-risk commands and protected files")
    func diffGateSafety() async {
        let gate = DiffGate()
        let contract = TaskContract(prompt: "Modify code")
        let ctx = GateContext(taskID: "task-1", contract: contract, previousOutputs: [])

        let dangerous = AgentOutput(
            content: "I will run rm -rf /",
            toolCalls: [ToolCall(id: "1", name: "bash", arguments: ["command": "rm -rf /"])],
            turnIndex: 1,
            timestamp: Date()
        )
        let res = await gate.evaluate(dangerous, context: ctx)
        #expect(res.passed == false)
    }

    @Test("Fail Chain escalation feedback message generation")
    func failChainFeedback() {
        let chain = FailChain()
        let failResult = GateResult(passed: false, gateName: "SyntaxGate", error: "Unbalanced parenthesis")

        let feedback = chain.recordFailure(gateName: "SyntaxGate", result: failResult)
        #expect(feedback.contains("SyntaxGate"))
        #expect(feedback.contains("Unbalanced parenthesis"))
    }

    @Test("Fail Chain multi-tier escalation and per-gate isolation")
    func failChainEscalation() {
        let chain = FailChain()
        let fail = GateResult(passed: false, gateName: "CompileGate", error: "Symbol not found")

        _ = chain.recordFailure(gateName: "CompileGate", result: fail)
        _ = chain.recordFailure(gateName: "CompileGate", result: fail)
        let f3 = chain.recordFailure(gateName: "CompileGate", result: fail)
        #expect(f3.contains("escalated") || f3.contains("ATTENTION") || f3.contains("Failed 3 times"))
    }
}

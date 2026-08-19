// GUI - ThreadGateCertifier
// Handles gate certification for agent output

import Foundation
import AdventurersCore

/// Certifies agent output through the 6-gate deterministic pipeline.
public struct ThreadGateCertifier: Sendable {
    public init() {}

    /// Certificate result with pass/fail status for each gate.
    public struct CertificationResult: Sendable {
        public let allPassed: Bool
        public let gateResults: [String: Bool]
        public let errors: [String: String]

        public init(allPassed: Bool, gateResults: [String: Bool], errors: [String: String]) {
            self.allPassed = allPassed
            self.gateResults = gateResults
            self.errors = errors
        }
    }

    /// Run all gates on the output and return certification results.
    public func certify(content: String, prompt: String) async -> CertificationResult {
        let contract = TaskContract(prompt: prompt, maxRounds: 15)
        let output = AgentOutput(content: content, toolCalls: [], turnIndex: 0, timestamp: Date())
        let context = GateContext(taskID: UUID().uuidString, contract: contract, previousOutputs: [output])

        let syntaxGate = SyntaxGate()
        let repeatGate = RepeatGate()
        let compilationGate = CompilationGate()
        let memoryGate = MemoryGate()
        let diffGate = DiffGate()
        let objectiveGate = ObjectiveGate()

        var gateResults: [String: Bool] = [:]
        var errors: [String: String] = [:]
        var allPassed = true

        // Run each gate
        let syntaxRes = await syntaxGate.evaluate(output, context: context)
        gateResults["syntax"] = syntaxRes.passed
        if !syntaxRes.passed { errors["syntax"] = syntaxRes.error; allPassed = false }

        let repeatRes = await repeatGate.evaluate(output, context: context)
        gateResults["repeat"] = repeatRes.passed
        if !repeatRes.passed { errors["repeat"] = repeatRes.error; allPassed = false }

        let compRes = await compilationGate.evaluate(output, context: context)
        gateResults["compilation"] = compRes.passed
        if !compRes.passed { errors["compilation"] = compRes.error; allPassed = false }

        let memRes = await memoryGate.evaluate(output, context: context)
        gateResults["memory"] = memRes.passed
        if !memRes.passed { errors["memory"] = memRes.error; allPassed = false }

        let diffRes = await diffGate.evaluate(output, context: context)
        gateResults["diff"] = diffRes.passed
        if !diffRes.passed { errors["diff"] = diffRes.error; allPassed = false }

        let objRes = await objectiveGate.evaluate(output, context: context)
        gateResults["objective"] = objRes.passed
        if !objRes.passed { errors["objective"] = objRes.error; allPassed = false }

        return CertificationResult(allPassed: allPassed, gateResults: gateResults, errors: errors)
    }
}

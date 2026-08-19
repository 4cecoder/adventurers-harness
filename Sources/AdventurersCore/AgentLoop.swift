// AdventurersCore - Agent Loop
// The core execution loop: propose -> gate -> verify -> repair

import Foundation
import LLMProviders

/// The agent loop orchestrates the propose-gate-certify cycle.
/// The model proposes work. The harness certifies completion.
public actor AgentLoop {
    private let config: HarnessConfig
    private let provider: LLMProvider
    private let gates: [Gate]
    private let tools: [String: Tool]
    private let journal: EventJournal
    private let failChain: FailChain

    public init(config: HarnessConfig, provider: LLMProvider, gates: [Gate], tools: [Tool]) {
        self.config = config
        self.provider = provider
        self.gates = gates
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        self.journal = EventJournal()
        self.failChain = FailChain()
    }

    public func execute(_ task: TaskContract) async throws -> TaskResult {
        var messages: [Message] = [
            Message(role: .system, content: systemPrompt(for: task)),
            Message(role: .user, content: task.prompt),
        ]
        var outputs: [AgentOutput] = []

        for round in 0..<task.maxRounds {
            await journal.append(.roundStart, payload: ["round": "\(round)", "taskID": task.taskID])

            let response = try await provider.send(messages: messages, config: config.llm)
            let output = AgentOutput(
                content: response.content,
                toolCalls: response.toolCalls,
                turnIndex: round,
                timestamp: Date()
            )
            outputs.append(output)

            var toolResults: [ToolResult] = []
            for call in output.toolCalls {
                guard let tool = tools[call.name] else { continue }
                let result = try await tool.execute(arguments: call.arguments)
                toolResults.append(result)
                await journal.append(.toolExecution, payload: ["tool": call.name, "success": "\(result.error == nil)"])
            }

            messages.append(Message(role: .assistant, content: response.content))
            for result in toolResults {
                let resultContent = result.error ?? result.output
                messages.append(Message(role: .tool, content: resultContent))
            }

            let gateContext = GateContext(taskID: task.taskID, contract: task, previousOutputs: outputs)
            let gateResults = await runGates(output: output, context: gateContext)

            let requiredGates = gates.filter(\.required)
            let allRequiredPassed = requiredGates.allSatisfy { gate in
                gateResults.first { $0.gateName == gate.name }?.passed ?? false
            }

            if allRequiredPassed {
                await journal.append(.taskCompleted, payload: ["round": "\(round)", "taskID": task.taskID])
                return TaskResult.success(output: output, rounds: round + 1, journal: journal)
            }

            let failures = gateResults.filter { !$0.passed }
            let mitigation = await failChain.mitigate(failures: failures)
            messages.append(Message(role: .user, content: mitigation))
            await journal.append(.gateFailed, payload: [
                "round": "\(round)",
                "failures": failures.map(\.gateName).joined(separator: ","),
            ])
        }

        await journal.append(.taskFailed, payload: ["taskID": task.taskID, "reason": "budget_exhausted"])
        return TaskResult.failed(rounds: task.maxRounds, journal: journal)
    }

    private func runGates(output: AgentOutput, context: GateContext) async -> [GateResult] {
        var results: [GateResult] = []
        for gate in gates {
            let result = await gate.evaluate(output, context: context)
            results.append(result)
            if !result.passed && gate.required {
                await failChain.record(gate: gate.name)
            } else if result.passed {
                await failChain.reset(gate: gate.name)
            }
        }
        return results
    }

    private func systemPrompt(for task: TaskContract) -> String {
        """
        You are Adventurers Harness, an AI coding agent.
        You write code, execute tools, and complete tasks.
        You do NOT decide when you are done. The harness gates certify completion.
        Follow the task contract exactly. Be concise.
        """
    }
}

public enum TaskResult: Sendable {
    case success(output: AgentOutput, rounds: Int, journal: EventJournal)
    case failed(rounds: Int, journal: EventJournal)

    public var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}

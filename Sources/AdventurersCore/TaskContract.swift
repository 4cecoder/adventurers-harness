// AdventurersCore - Task Contract
// Immutable boundary for agent execution

import Foundation

/// A TaskContract defines the scope and constraints for a single agent task.
public struct TaskContract: Sendable {
    public let taskID: String
    public let prompt: String
    public let maxRounds: Int
    public let requiredGates: [String]
    public let createdAt: Date

    private var currentRound: Int = 0

    public let maxTokens: Int
    public private(set) var consumedTokens: Int = 0

    public init(taskID: String = UUID().uuidString, prompt: String, maxRounds: Int = 4,
                requiredGates: [String] = ["syntax", "repeat"], maxTokens: Int = 100_000) {
        self.taskID = taskID
        self.prompt = prompt
        self.maxRounds = maxRounds
        self.requiredGates = requiredGates
        self.maxTokens = maxTokens
        self.createdAt = Date()
    }

    public var remainingRounds: Int { maxRounds - currentRound }
    public var remainingTokens: Int { max(0, maxTokens - consumedTokens) }

    public mutating func bumpRound() throws -> Int {
        guard currentRound < maxRounds else {
            throw ContractError.budgetExhausted(taskID: taskID)
        }
        currentRound += 1
        return currentRound
    }

    public mutating func recordTokens(prompt: Int, completion: Int) throws {
        let total = prompt + completion
        guard consumedTokens + total <= maxTokens else {
            throw ContractError.tokenBudgetExhausted(taskID: taskID, requested: consumedTokens + total, limit: maxTokens)
        }
        consumedTokens += total
    }
}

public enum ContractError: Error, Sendable {
    case budgetExhausted(taskID: String)
    case tokenBudgetExhausted(taskID: String, requested: Int, limit: Int)
}

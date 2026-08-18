// AdventurersCore - Task Contract
// Immutable boundary for agent execution

import Foundation

/// A TaskContract defines the scope and constraints for a single agent task.
/// The harness reads it. The agent never modifies it.
public struct TaskContract: Sendable {
    public let taskID: String
    public let prompt: String
    public let maxRounds: Int
    public let requiredGates: [String]
    public let createdAt: Date

    private var currentRound: Int = 0

    public init(taskID: String = UUID().uuidString, prompt: String, maxRounds: Int = 4,
                requiredGates: [String] = ["syntax", "repeat"]) {
        self.taskID = taskID
        self.prompt = prompt
        self.maxRounds = maxRounds
        self.requiredGates = requiredGates
        self.createdAt = Date()
    }

    public var remainingRounds: Int { maxRounds - currentRound }

    public mutating func bumpRound() throws -> Int {
        guard currentRound < maxRounds else {
            throw ContractError.budgetExhausted(taskID: taskID)
        }
        currentRound += 1
        return currentRound
    }
}

public enum ContractError: Error, Sendable {
    case budgetExhausted(taskID: String)
}

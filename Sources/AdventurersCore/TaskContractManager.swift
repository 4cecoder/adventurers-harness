// AdventurersCore - Pure Swift Long-Horizon Task Contract Manager
// Implements Hermes-style plan verification, phase gating, and checklist tracking.

import Foundation

// MARK: - Task Phases & Checklist Models

public enum TaskPhase: String, Sendable, Codable, CaseIterable {
    case planning = "Planning & Discovery"
    case execution = "Execution & Patching"
    case verification = "Gate Verification"
    case completed = "Completed & Certified"
    case rolledBack = "Rolled Back"

    public var icon: String {
        switch self {
        case .planning: return "magnifyingglass.circle.fill"
        case .execution: return "wrench.and.screwdriver.fill"
        case .verification: return "checkmark.seal.fill"
        case .completed: return "flag.checkered.circle.fill"
        case .rolledBack: return "arrow.uturn.backward.circle.fill"
        }
    }
}

public struct TaskChecklistStep: Sendable, Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public var isCurrent: Bool
    public var toolInvocationsCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        isCurrent: Bool = false,
        toolInvocationsCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.isCurrent = isCurrent
        self.toolInvocationsCount = toolInvocationsCount
    }
}

public struct LongHorizonTaskContract: Sendable, Codable, Identifiable {
    public let id: UUID
    public var goal: String
    public var acceptanceCriteria: [String]
    public var currentPhase: TaskPhase
    public var steps: [TaskChecklistStep]
    public var turnBudget: Int
    public var turnsConsumed: Int
    public var checkpointsSaved: Int

    public init(
        id: UUID = UUID(),
        goal: String,
        acceptanceCriteria: [String] = [],
        currentPhase: TaskPhase = .planning,
        steps: [TaskChecklistStep] = [],
        turnBudget: Int = 12,
        turnsConsumed: Int = 0,
        checkpointsSaved: Int = 0
    ) {
        self.id = id
        self.goal = goal
        self.acceptanceCriteria = acceptanceCriteria
        self.currentPhase = currentPhase
        self.steps = steps
        self.turnBudget = turnBudget
        self.turnsConsumed = turnsConsumed
        self.checkpointsSaved = checkpointsSaved
    }

    public var progressFraction: Double {
        guard !steps.isEmpty else {
            return currentPhase == .completed ? 1.0 : (currentPhase == .verification ? 0.8 : 0.2)
        }
        let completedCount = steps.filter(\.isCompleted).count
        return Double(completedCount) / Double(steps.count)
    }

    public var formattedSummary: String {
        return "Phase: \(currentPhase.rawValue) • Steps: \(steps.filter(\.isCompleted).count)/\(steps.count) • Checkpoints: \(checkpointsSaved)"
    }
}

// MARK: - Task Contract State Engine

public actor TaskContractManager {
    public static let shared = TaskContractManager()

    private var activeContracts: [UUID: LongHorizonTaskContract] = [:]

    public init() {}

    public func getContract(for sessionID: UUID) -> LongHorizonTaskContract? {
        return activeContracts[sessionID]
    }

    public func initializeContract(
        sessionID: UUID,
        goal: String,
        criteria: [String] = [],
        steps: [String] = []
    ) -> LongHorizonTaskContract {
        let checklistSteps = steps.enumerated().map { idx, s in
            TaskChecklistStep(title: s, isCompleted: false, isCurrent: idx == 0)
        }
        let contract = LongHorizonTaskContract(
            goal: goal,
            acceptanceCriteria: criteria,
            currentPhase: .planning,
            steps: checklistSteps
        )
        activeContracts[sessionID] = contract
        return contract
    }

    public func transitionPhase(sessionID: UUID, to newPhase: TaskPhase) -> LongHorizonTaskContract? {
        guard var contract = activeContracts[sessionID] else { return nil }
        contract.currentPhase = newPhase
        activeContracts[sessionID] = contract
        return contract
    }

    public func completeStep(sessionID: UUID, stepIndex: Int) -> LongHorizonTaskContract? {
        guard var contract = activeContracts[sessionID], stepIndex < contract.steps.count else { return nil }
        contract.steps[stepIndex].isCompleted = true
        contract.steps[stepIndex].isCurrent = false
        if stepIndex + 1 < contract.steps.count {
            contract.steps[stepIndex + 1].isCurrent = true
        }
        activeContracts[sessionID] = contract
        return contract
    }

    public func recordCheckpoint(sessionID: UUID) {
        guard var contract = activeContracts[sessionID] else { return }
        contract.checkpointsSaved += 1
        activeContracts[sessionID] = contract
    }

    public func clear(sessionID: UUID) {
        activeContracts.removeValue(forKey: sessionID)
    }
}

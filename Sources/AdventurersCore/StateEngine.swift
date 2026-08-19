// AdventurersCore - FSM (Finite State Machine)
// Enforced state transitions for the agent lifecycle

import Foundation

/// Agent lifecycle states with enforced transitions.
public enum AgentState: String, Sendable, CaseIterable {
    case idle
    case taskingested
    case proposing
    case validatingSyntax
    case compiling
    case executingTest
    case verified
    case retrying
    case failed

    public var allowedTransitions: Set<AgentState> {
        switch self {
        case .idle: return [.taskingested]
        case .taskingested: return [.proposing, .failed]
        case .proposing: return [.validatingSyntax, .failed]
        case .validatingSyntax: return [.compiling, .retrying, .failed]
        case .compiling: return [.executingTest, .retrying, .failed]
        case .executingTest: return [.verified, .retrying, .failed]
        case .verified: return [.idle]
        case .retrying: return [.proposing]
        case .failed: return [.idle]
        }
    }
}

public actor StateEngine {
    private var currentState: AgentState = .idle
    private var stateHistory: [(state: AgentState, timestamp: Date)] = []

    public init() {}

    public func transition(to newState: AgentState) throws {
        guard currentState.allowedTransitions.contains(newState) else {
            throw StateError.invalidTransition(from: currentState, to: newState)
        }
        currentState = newState
        stateHistory.append((newState, Date()))
    }

    public func current() -> AgentState { currentState }
    public func history() -> [(state: AgentState, timestamp: Date)] { stateHistory }
}

public enum StateError: Error, Sendable {
    case invalidTransition(from: AgentState, to: AgentState)
}

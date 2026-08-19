// AdventurersCore - Guardian Circuit Breaker & Fail-Closed Safety System
// Implements dual-threshold anomaly detection: consecutive failures (3) + sliding window (10/50).
// Fail-Closed principle: Any evaluation error, timeout, or ambiguity defaults strictly to DENY.

import Foundation

public enum GuardianDecision: Sendable, Equatable {
    case allow
    case deny(reason: String, circuitTripped: Bool)
    case requiresConfirmation(reason: String)
}

public actor GuardianCircuitBreaker {
    public static let shared = GuardianCircuitBreaker()

    // Configurable Circuit Breaker Thresholds
    public let maxConsecutiveFailures: Int
    public let slidingWindowSize: Int
    public let maxWindowFailures: Int

    // State Tracking
    private var consecutiveFailuresCount: Int = 0
    private var recentExecutionHistory: [Bool] = [] // true = success, false = failure/anomaly
    private var isCircuitTripped: Bool = false
    private var trippedReason: String?

    public init(
        maxConsecutiveFailures: Int = 3,
        slidingWindowSize: Int = 50,
        maxWindowFailures: Int = 10
    ) {
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.slidingWindowSize = slidingWindowSize
        self.maxWindowFailures = maxWindowFailures
    }

    /// Evaluates whether a proposed tool execution or agent action is permitted.
    /// Strict Fail-Closed Guarantee: Any failure or unhandled condition returns .deny.
    public func evaluate(command: String, toolName: String) -> GuardianDecision {
        if isCircuitTripped {
            let reason = trippedReason ?? "Guardian Circuit Breaker is active (tripped by anomaly thresholds)."
            return .deny(reason: reason, circuitTripped: true)
        }

        // Check sliding window failure density
        let windowFailures = recentExecutionHistory.suffix(slidingWindowSize).filter { !$0 }.count
        if windowFailures >= maxWindowFailures {
            tripCircuit(reason: "Exceeded sliding window failure threshold (\(windowFailures)/\(slidingWindowSize) failed turns).")
            return .deny(reason: trippedReason!, circuitTripped: true)
        }

        // Check consecutive failure streak
        if consecutiveFailuresCount >= maxConsecutiveFailures {
            tripCircuit(reason: "Exceeded maximum consecutive failure threshold (\(consecutiveFailuresCount) consecutive failures).")
            return .deny(reason: trippedReason!, circuitTripped: true)
        }

        return .allow
    }

    /// Records the result of an execution step.
    public func recordExecution(success: Bool, errorDescription: String? = nil) {
        recentExecutionHistory.append(success)
        if recentExecutionHistory.count > slidingWindowSize * 2 {
            recentExecutionHistory.removeFirst(recentExecutionHistory.count - slidingWindowSize)
        }

        if success {
            consecutiveFailuresCount = 0
        } else {
            consecutiveFailuresCount += 1
            if consecutiveFailuresCount >= maxConsecutiveFailures {
                tripCircuit(reason: "Tripped after \(consecutiveFailuresCount) consecutive failures: \(errorDescription ?? "unknown error")")
            }
        }
    }

    /// Explicitly trips the circuit breaker.
    public func tripCircuit(reason: String) {
        isCircuitTripped = true
        trippedReason = reason
    }

    /// Resets the circuit breaker following human review or checkpoint rollback.
    public func resetCircuit() {
        isCircuitTripped = false
        trippedReason = nil
        consecutiveFailuresCount = 0
        recentExecutionHistory.removeAll()
    }

    public var status: (tripped: Bool, reason: String?, consecutiveFailures: Int, windowFailures: Int) {
        let windowFails = recentExecutionHistory.suffix(slidingWindowSize).filter { !$0 }.count
        return (isCircuitTripped, trippedReason, consecutiveFailuresCount, windowFails)
    }
}

// AdventurersCore - Fail Chain
// Escalating capsule feedback for repeated gate failures

import Foundation

/// Tracks consecutive failures per gate and generates escalating feedback.
/// First failure: gentle hint. Second: stern directive.
public actor FailChain {
    private var consecutiveFailures: [String: Int] = [:]

    public init() {}

    public func record(gate: String) {
        consecutiveFailures[gate, default: 0] += 1
    }

    public func reset(gate: String) {
        consecutiveFailures[gate] = nil
    }

    public func count(for gate: String) -> Int {
        consecutiveFailures[gate] ?? 0
    }

    /// Generate escalating mitigation feedback for failed gates.
    public func mitigate(failures: [GateResult]) -> String {
        var feedback: [String] = []

        for failure in failures {
            let count = consecutiveFailures[failure.gateName] ?? 1
            feedback.append(mitigation(gate: failure.gateName, error: failure.error ?? "unknown", consecutive: count))
        }

        return """
        The harness gates rejected your output:

        \(feedback.joined(separator: "\n\n"))

        Fix the issues above and try again. Do NOT repeat the same approach.
        """
    }

    private func mitigation(gate: String, error: String, consecutive: Int) -> String {
        switch consecutive {
        case 1:
            return """
            Gate '\(gate)' failed: \(error)
            Please review and fix the issue.
            """
        case 2:
            return """
            Gate '\(gate)' failed AGAIN: \(error)
            You must fix this specific issue. Do not repeat the same code.
            Previous attempt was identical. Try a different approach.
            """
        default:
            return """
            CRITICAL: Gate '\(gate)' has failed \(consecutive) consecutive times.
            Error: \(error)
            STOP repeating the same broken approach. You must:
            1. Identify what specifically is wrong
            2. Use a completely different approach
            3. Verify your fix before submitting
            """
        }
    }
}

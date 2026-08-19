// AdventurersCore - Fail Chain
// Escalating capsule feedback for repeated gate failures

import Foundation

/// Tracks consecutive failures per gate and generates escalating feedback.
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
            return "Gate '\(gate)' failed: \(error)\nPlease review and fix the issue."
        case 2:
            return "Gate '\(gate)' failed AGAIN: \(error)\nYou must fix this specific issue. Do not repeat the same code."
        default:
            return "CRITICAL: Gate '\(gate)' has failed \(consecutive) consecutive times.\nError: \(error)\nSTOP repeating the same broken approach."
        }
    }
}

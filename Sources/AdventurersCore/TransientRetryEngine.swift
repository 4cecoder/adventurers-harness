// AdventurersCore - Specific Transient Error Retry Engine
// Implements exponential backoff with jitter ONLY for transient transport/server errors.
// NEVER retries permanent authorization, client bad request, or invalid parameter errors.

import Foundation

public enum ErrorClassification: Sendable, Equatable {
    case transient(suggestedDelay: TimeInterval)
    case permanent(reason: String)
}

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let initialDelaySeconds: Double
    public let maxDelaySeconds: Double
    public let backoffMultiplier: Double
    public let jitterFactor: Double

    public init(
        maxAttempts: Int = 3,
        initialDelaySeconds: Double = 0.5,
        maxDelaySeconds: Double = 8.0,
        backoffMultiplier: Double = 2.0,
        jitterFactor: Double = 0.2
    ) {
        self.maxAttempts = maxAttempts
        self.initialDelaySeconds = initialDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
        self.backoffMultiplier = backoffMultiplier
        self.jitterFactor = jitterFactor
    }
}

public final class TransientRetryEngine: Sendable {
    public static let shared = TransientRetryEngine()

    public init() {}

    /// Classifies an error into transient vs permanent.
    public func classify(statusCode: Int?, error: Error?) -> ErrorClassification {
        // HTTP Status Code Checks
        if let code = statusCode {
            switch code {
            case 429:
                // Rate limited (transient)
                return .transient(suggestedDelay: 2.0)
            case 500, 502, 503, 504:
                // Server overloaded / gateway error (transient)
                return .transient(suggestedDelay: 1.0)
            case 401, 403:
                // Authentication / Permission (permanent)
                return .permanent(reason: "Authentication or permission denied (HTTP \(code)). Check API keys.")
            case 400:
                // Bad request / schema mismatch (permanent)
                return .permanent(reason: "Bad Request (HTTP 400). Payload formatting or parameter error.")
            default:
                break
            }
        }

        // Error message string heuristics
        if let err = error {
            let msg = err.localizedDescription.lowercased()
            if msg.contains("connection reset") ||
               msg.contains("timed out") ||
               msg.contains("overloaded") ||
               msg.contains("network connection was lost") ||
               msg.contains("can't connect to host") {
                return .transient(suggestedDelay: 1.0)
            }
            if msg.contains("invalid_api_key") ||
               msg.contains("unauthorized") ||
               msg.contains("insufficient_quota") {
                return .permanent(reason: "Invalid API credentials or account quota exhausted.")
            }
        }

        // Default to permanent fail-closed
        return .permanent(reason: "Unclassified failure. Failing closed to prevent retry storm.")
    }

    /// Calculates exponential backoff delay with random jitter for a given attempt.
    public func calculateDelay(attempt: Int, policy: RetryPolicy) -> TimeInterval {
        let exponential = policy.initialDelaySeconds * pow(policy.backoffMultiplier, Double(attempt - 1))
        let bounded = min(exponential, policy.maxDelaySeconds)
        let jitter = bounded * Double.random(in: -policy.jitterFactor...policy.jitterFactor)
        return max(0.1, bounded + jitter)
    }

    /// Executes an async throwing closure with targeted transient retries.
    public func withRetry<T: Sendable>(
        policy: RetryPolicy = RetryPolicy(),
        operationName: String = "Operation",
        operation: @Sendable () async throws -> (result: T, statusCode: Int?)
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...policy.maxAttempts {
            do {
                let (result, statusCode) = try await operation()
                let classification = classify(statusCode: statusCode, error: nil)
                if case .permanent(let reason) = classification {
                    throw NSError(domain: "TransientRetryEngine", code: statusCode ?? 400, userInfo: [NSLocalizedDescriptionKey: reason])
                }
                return result
            } catch {
                lastError = error
                let classification = classify(statusCode: nil, error: error)
                switch classification {
                case .transient:
                    if attempt < policy.maxAttempts {
                        let delay = calculateDelay(attempt: attempt, policy: policy)
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                case .permanent:
                    throw error
                }
            }
        }
        throw lastError ?? NSError(domain: "TransientRetryEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retry attempts exceeded for \(operationName)"])
    }
}

// AdventurersCore - Pure Swift Alignment & Precision Grilling Engine
// Evaluates ambiguous user requests, detects high-risk underspecified assumptions,
// and formulates structured clarification probes to enforce rigid, verified results.

import Foundation

// MARK: - Alignment Models

public struct ClarificationProbe: Sendable, Codable, Identifiable {
    public let id: UUID
    public let question: String
    public let options: [String]
    public let rationale: String
    public let riskCategory: String

    public init(
        id: UUID = UUID(),
        question: String,
        options: [String],
        rationale: String,
        riskCategory: String
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.rationale = rationale
        self.riskCategory = riskCategory
    }
}

public struct AlignmentEvaluation: Sendable, Codable {
    public let requiresClarification: Bool
    public let confidenceScore: Double // 0.0 to 1.0
    public let probes: [ClarificationProbe]
    public let verifiedIntentSummary: String

    public init(
        requiresClarification: Bool,
        confidenceScore: Double,
        probes: [ClarificationProbe] = [],
        verifiedIntentSummary: String
    ) {
        self.requiresClarification = requiresClarification
        self.confidenceScore = confidenceScore
        self.probes = probes
        self.verifiedIntentSummary = verifiedIntentSummary
    }
}

// MARK: - Alignment Griller Engine

public final class AlignmentGriller: Sendable {
    public static let shared = AlignmentGriller()

    public init() {}

    /// Evaluates if a prompt is underspecified, destructive, or ambiguous and generates precision probes.
    public func evaluateIntent(prompt: String, workspaceFiles: [String] = []) -> AlignmentEvaluation {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Explicit /grill-me command
        if lower.hasPrefix("/grill-me") || lower.contains("grill me") {
            let probe = ClarificationProbe(
                question: "What are your exact acceptance criteria and constraints for this architecture?",
                options: [
                    "Strict backward compatibility with zero breaking API changes",
                    "Performance first (zero allocation, maximum throughput)",
                    "Minimal footprint with pure standard library dependencies"
                ],
                rationale: "User explicitly requested an alignment grilling session to lock requirements.",
                riskCategory: "Architecture Alignment"
            )
            return AlignmentEvaluation(
                requiresClarification: true,
                confidenceScore: 0.3,
                probes: [probe],
                verifiedIntentSummary: "Alignment interview triggered by user."
            )
        }

        // 2. High Ambiguity & Destructive Overhaul Signals
        if (lower == "fix it" || lower.hasPrefix("fix it") || lower == "do it" || lower.contains("rewrite everything") || lower.contains("clean up the whole codebase") || lower.contains("make it better")) && trimmed.count < 60 {
            let probe = ClarificationProbe(
                question: "The request is broad or underspecified. Which area should be targeted first?",
                options: [
                    "Refactor core data models and state management",
                    "Improve error handling and unit test coverage",
                    "Optimize memory and performance bottlenecks"
                ],
                rationale: "Broad, underspecified request could cause unintended cross-module disruption.",
                riskCategory: "Scope Underspecification"
            )
            return AlignmentEvaluation(
                requiresClarification: true,
                confidenceScore: 0.4,
                probes: [probe],
                verifiedIntentSummary: "Scope requires boundary selection."
            )
        }

        // 3. Clear, direct, or well-specified intent
        return AlignmentEvaluation(
            requiresClarification: false,
            confidenceScore: 0.95,
            probes: [],
            verifiedIntentSummary: trimmed
        )
    }
}

// AdventurersCore - Pure Swift Semi-Deterministic Task Complexity Judger & Fast-Path Pipeline
// Classifies user intent into optimal execution tiers to minimize round-trip turns and maximize token savings.

import Foundation

// MARK: - Task Complexity Tiers

public enum TaskComplexityTier: String, Sendable, Codable, CaseIterable {
    case fastDirect = "Fast-Path (Direct Answer)"
    case singleToolBatch = "Single Tool Batch (1-2 Turns)"
    case mediumAction = "Scoped Action (3-5 Turns)"
    case longHorizon = "Long-Horizon Engine (Full Multi-Turn)"

    public var icon: String {
        switch self {
        case .fastDirect: return "bolt.fill"
        case .singleToolBatch: return "bolt.horizontal.fill"
        case .mediumAction: return "wrench.and.screwdriver.fill"
        case .longHorizon: return "map.fill"
        }
    }

    public var defaultTurnBudget: Int {
        switch self {
        case .fastDirect: return 1
        case .singleToolBatch: return 2
        case .mediumAction: return 5
        case .longHorizon: return 12
        }
    }
}

// MARK: - Judger Decision Model

public struct TaskJudgerDecision: Sendable, Codable {
    public let tier: TaskComplexityTier
    public let recommendedTurnBudget: Int
    public let shouldInitializeTaskContract: Bool
    public let shouldEnableAutoCheckpoints: Bool
    public let systemGuidanceSnippet: String
    public let reason: String
    public let estimatedTokenSavingsPercent: Double

    public init(
        tier: TaskComplexityTier,
        recommendedTurnBudget: Int,
        shouldInitializeTaskContract: Bool,
        shouldEnableAutoCheckpoints: Bool,
        systemGuidanceSnippet: String,
        reason: String,
        estimatedTokenSavingsPercent: Double
    ) {
        self.tier = tier
        self.recommendedTurnBudget = recommendedTurnBudget
        self.shouldInitializeTaskContract = shouldInitializeTaskContract
        self.shouldEnableAutoCheckpoints = shouldEnableAutoCheckpoints
        self.systemGuidanceSnippet = systemGuidanceSnippet
        self.reason = reason
        self.estimatedTokenSavingsPercent = estimatedTokenSavingsPercent
    }
}

// MARK: - Task Judger Engine

public final class TaskJudgerEngine: Sendable {
    public static let shared = TaskJudgerEngine()

    public init() {}

    /// Evaluates a user prompt and conversation history to determine the optimal streamlined pipeline tier.
    public func evaluate(
        prompt: String,
        historyCount: Int = 0,
        hasModifiedFiles: Bool = false
    ) -> TaskJudgerDecision {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Check for Explicit Slash Commands
        if lower.hasPrefix("/plan") || lower.hasPrefix("/goal") || lower.contains("long-horizon") || lower.contains("multi-step") {
            return TaskJudgerDecision(
                tier: .longHorizon,
                recommendedTurnBudget: 12,
                shouldInitializeTaskContract: true,
                shouldEnableAutoCheckpoints: true,
                systemGuidanceSnippet: "CRITICAL: Plan all steps upfront in structured milestone phases. Check each tool output before proceeding.",
                reason: "Explicit long-horizon command or contract requested.",
                estimatedTokenSavingsPercent: 0.0
            )
        }

        // 2. Fast-Path: Pure Informational, Conceptual, or Explanation Queries
        let explanationPrefixes = [
            "what is", "what are", "what does", "how does", "how do i", "explain",
            "why is", "why does", "tell me about", "describe", "can you clarify", "difference between"
        ]
        let isDirectQuery = explanationPrefixes.contains { lower.hasPrefix($0) } || (lower.hasSuffix("?") && !lower.contains("fix") && !lower.contains("modify") && !lower.contains("refactor") && !lower.contains("build"))

        if isDirectQuery && !hasActionKeywords(lower) {
            return TaskJudgerDecision(
                tier: .fastDirect,
                recommendedTurnBudget: 1,
                shouldInitializeTaskContract: false,
                shouldEnableAutoCheckpoints: false,
                systemGuidanceSnippet: "FAST-PATH: Answer directly, concisely, and accurately in a single turn without calling unnecessary tools.",
                reason: "Informational or explanation request. Resolved in a single direct answer.",
                estimatedTokenSavingsPercent: 85.0
            )
        }

        // 3. Single Tool Batch: Targeted Inspections, Status, or Single File Reads
        let singleToolKeywords = [
            "git status", "run test", "swift test", "npm test", "show me file", "view file",
            "find symbol", "grep", "search for", "list files", "where is"
        ]
        let isSingleBatch = singleToolKeywords.contains { lower.contains($0) } || (trimmed.count < 80 && (lower.contains("find") || lower.contains("check") || lower.contains("inspect")))

        if isSingleBatch && !isMultiFileRefactor(lower) {
            return TaskJudgerDecision(
                tier: .singleToolBatch,
                recommendedTurnBudget: 2,
                shouldInitializeTaskContract: false,
                shouldEnableAutoCheckpoints: false,
                systemGuidanceSnippet: "STREAMLINED: Execute required inspection tools in one batch and synthesize the concise result immediately.",
                reason: "Targeted single inspection or command run. Minimum turn round-trips.",
                estimatedTokenSavingsPercent: 60.0
            )
        }

        // 4. Long-Horizon Architecture & Cross-Module Refactor Signals
        if isMultiFileRefactor(lower) || trimmed.count > 400 {
            return TaskJudgerDecision(
                tier: .longHorizon,
                recommendedTurnBudget: 12,
                shouldInitializeTaskContract: true,
                shouldEnableAutoCheckpoints: true,
                systemGuidanceSnippet: "LONG-HORIZON: Formulate execution plan, apply atomic changes, and verify gates before concluding.",
                reason: "Broad multi-file refactor or complex engineering task detected.",
                estimatedTokenSavingsPercent: 15.0
            )
        }

        // 5. Default: Scoped Action (Fix, Edit, or localized feature)
        return TaskJudgerDecision(
            tier: .mediumAction,
            recommendedTurnBudget: 4,
            shouldInitializeTaskContract: false,
            shouldEnableAutoCheckpoints: true,
            systemGuidanceSnippet: "SCOPED ACTION: Apply necessary modifications directly to target files and verify in minimal round-trips.",
            reason: "Standard code edit or localized bug fix.",
            estimatedTokenSavingsPercent: 40.0
        )
    }

    private func hasActionKeywords(_ text: String) -> Bool {
        let actionKeywords = [
            "fix", "modify", "edit", "change", "refactor", "update", "delete", "create",
            "implement", "build", "patch", "replace", "install", "add file", "write"
        ]
        return actionKeywords.contains { text.contains($0) }
    }

    private func isMultiFileRefactor(_ text: String) -> Bool {
        let multiFileKeywords = [
            "refactor the whole", "across all files", "entire codebase", "multi-module",
            "architecture migration", "full redesign", "upgrade all", "rewrite the"
        ]
        return multiFileKeywords.contains { text.contains($0) }
    }
}

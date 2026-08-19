// Sources/AdventurersCore/ContextCompactor.swift
// AdventurersCore — Context Compaction v2 with Anchor Preservation & Token Budget
//
// macOS 15+ · Swift 6 · Sendable-safe
// Inspired by OpenAI Codex compact_remote_v2 and compact_token_budget architecture

import Foundation
import LLMProviders

// MARK: - Context Compactor Configuration

public struct ContextCompactorConfig: Sendable, Codable, Equatable {
    /// Number of initial turns to unconditionally protect (system prompt + task contract + initial instructions).
    public var headTurnsCount: Int
    /// Number of trailing turns to unconditionally protect verbatim for recency context.
    public var tailTurnsCount: Int
    /// Threshold ratio of model context window that triggers compaction (e.g. 0.75 = 75%).
    public var triggerThresholdRatio: Double
    /// Default context limit used when not specified per-model.
    public var defaultContextLimit: Int
    /// Maximum character length for middle window summary synthesis.
    public var maxSummaryLength: Int

    public init(
        headTurnsCount: Int = 2,
        tailTurnsCount: Int = 4,
        triggerThresholdRatio: Double = 0.75,
        defaultContextLimit: Int = 128_000,
        maxSummaryLength: Int = 4000
    ) {
        self.headTurnsCount = max(1, headTurnsCount)
        self.tailTurnsCount = max(1, tailTurnsCount)
        self.triggerThresholdRatio = min(1.0, max(0.1, triggerThresholdRatio))
        self.defaultContextLimit = max(1000, defaultContextLimit)
        self.maxSummaryLength = max(500, maxSummaryLength)
    }
}

// MARK: - Token Budget Estimator

public struct TokenBudgetEstimator: Sendable {
    public init() {}

    /// Fast token count heuristic (~4 characters per token + framing overhead).
    public func estimateTokens(for text: String) -> Int {
        if text.isEmpty { return 0 }
        return max(1, (text.count + 3) / 4)
    }

    /// Estimates token count for a Message.
    public func estimateTokens(for message: Message) -> Int {
        // Base content + 4 tokens role/metadata envelope
        estimateTokens(for: message.content) + 4
    }

    /// Estimates total tokens across a list of Messages.
    public func estimateTokens(for messages: [Message]) -> Int {
        messages.reduce(0) { $0 + estimateTokens(for: $1) }
    }

    /// Estimates token count for a TrajectoryTurn.
    public func estimateTokens(for turn: TrajectoryTurn) -> Int {
        turn.tokenCountEstimate
    }

    /// Estimates total tokens across a list of TrajectoryTurns.
    public func estimateTokens(for turns: [TrajectoryTurn]) -> Int {
        turns.reduce(0) { $0 + estimateTokens(for: $1) }
    }

    /// Calculates available headroom before reaching context window limit.
    public func contextHeadroom(consumed: Int, contextLimit: Int) -> Int {
        max(0, contextLimit - consumed)
    }

    /// Computes token utilization ratio (consumed / limit).
    public func utilizationRatio(consumed: Int, contextLimit: Int) -> Double {
        guard contextLimit > 0 else { return 1.0 }
        return Double(consumed) / Double(contextLimit)
    }

    /// Evaluates context health status based on token consumption.
    public func healthStatus(consumed: Int, contextLimit: Int) -> ContextHealthStatus {
        let ratio = utilizationRatio(consumed: consumed, contextLimit: contextLimit)
        if ratio <= 0.50 {
            return .optimal
        } else if ratio < 0.70 {
            return .moderate
        } else if ratio < 0.85 {
            return .high
        } else {
            return .critical
        }
    }

    /// Determines if compaction should be triggered given consumption and context limit.
    public func shouldTriggerCompaction(
        consumedTokens: Int,
        contextLimit: Int,
        thresholdRatio: Double = 0.75
    ) -> Bool {
        guard contextLimit > 0 else { return false }
        return Double(consumedTokens) >= (Double(contextLimit) * thresholdRatio)
    }

    /// Determines if compaction should be triggered for a list of Messages.
    public func shouldTriggerCompaction(
        messages: [Message],
        contextLimit: Int,
        thresholdRatio: Double = 0.75
    ) -> Bool {
        let consumed = estimateTokens(for: messages)
        return shouldTriggerCompaction(consumedTokens: consumed, contextLimit: contextLimit, thresholdRatio: thresholdRatio)
    }

    /// Determines if compaction should be triggered for a list of TrajectoryTurns.
    public func shouldTriggerCompaction(
        turns: [TrajectoryTurn],
        contextLimit: Int,
        thresholdRatio: Double = 0.75
    ) -> Bool {
        let consumed = estimateTokens(for: turns)
        return shouldTriggerCompaction(consumedTokens: consumed, contextLimit: contextLimit, thresholdRatio: thresholdRatio)
    }
}

// MARK: - Role Alternation Validator

public struct RoleAlternationReport: Sendable, Equatable {
    public let isValid: Bool
    public let consecutiveRoleViolations: Int
    public let invalidLeadRole: Bool
    public let totalMessagesCount: Int

    public init(
        isValid: Bool,
        consecutiveRoleViolations: Int = 0,
        invalidLeadRole: Bool = false,
        totalMessagesCount: Int = 0
    ) {
        self.isValid = isValid
        self.consecutiveRoleViolations = consecutiveRoleViolations
        self.invalidLeadRole = invalidLeadRole
        self.totalMessagesCount = totalMessagesCount
    }
}

public struct RoleAlternationValidator: Sendable {
    public init() {}

    /// Validates whether a sequence of Messages alternates roles properly without consecutive duplicates.
    public func validate(messages: [Message]) -> RoleAlternationReport {
        guard !messages.isEmpty else {
            return RoleAlternationReport(isValid: true, consecutiveRoleViolations: 0, invalidLeadRole: false, totalMessagesCount: 0)
        }

        var violations = 0
        var prevRole: Message.Role? = nil

        for (index, msg) in messages.enumerated() {
            if let prev = prevRole {
                // Consecutive identical non-system roles violate strict alternation
                if prev == msg.role && msg.role != .system {
                    violations += 1
                }
            } else {
                // First non-system message check
                if msg.role != .system && msg.role != .user && index == 0 {
                    // LLMs usually expect initial user prompt or system prompt
                }
            }
            prevRole = msg.role
        }

        return RoleAlternationReport(
            isValid: violations == 0,
            consecutiveRoleViolations: violations,
            invalidLeadRole: false,
            totalMessagesCount: messages.count
        )
    }

    /// Validates whether a sequence of TrajectoryTurns alternates roles properly.
    public func validate(turns: [TrajectoryTurn]) -> Bool {
        guard !turns.isEmpty else { return true }
        var prevRole: String? = nil

        for turn in turns {
            if let prev = prevRole, prev == turn.role, turn.role != "system" {
                return false
            }
            prevRole = turn.role
        }
        return true
    }

    /// Repairs Message sequence by consolidating adjacent same-role messages and ensuring proper conversational turn flow.
    public func repairAlternation(messages: [Message]) -> [Message] {
        guard !messages.isEmpty else { return [] }

        var repaired: [Message] = []

        for msg in messages {
            guard let last = repaired.last else {
                repaired.append(msg)
                continue
            }

            if last.role == msg.role {
                // Merge adjacent messages with identical roles
                let mergedContent = "\(last.content)\n\n\(msg.content)"
                repaired.removeLast()
                repaired.append(Message(role: last.role, content: mergedContent))
            } else {
                repaired.append(msg)
            }
        }

        return repaired
    }

    /// Repairs TrajectoryTurn sequence by consolidating adjacent same-role turns.
    public func repairAlternation(turns: [TrajectoryTurn]) -> [TrajectoryTurn] {
        guard !turns.isEmpty else { return [] }

        var repaired: [TrajectoryTurn] = []

        for turn in turns {
            guard let last = repaired.last else {
                repaired.append(turn)
                continue
            }

            if last.role == turn.role {
                let mergedContent = "\(last.content)\n\n\(turn.content)"
                let combinedToolCalls = (last.toolCalls ?? []) + (turn.toolCalls ?? [])
                let updatedTurn = TrajectoryTurn(
                    id: last.id,
                    role: last.role,
                    content: mergedContent,
                    toolCalls: combinedToolCalls.isEmpty ? nil : combinedToolCalls,
                    tokenCountEstimate: max(1, mergedContent.count / 4)
                )
                repaired.removeLast()
                repaired.append(updatedTurn)
            } else {
                repaired.append(turn)
            }
        }

        return repaired
    }
}

// MARK: - Progress Milestone Model

public struct CompactedMilestone: Sendable, Codable, Equatable {
    public let compactedTurnsCount: Int
    public let toolOperationsCount: Int
    public let keyMilestones: [String]
    public let formattedXML: String

    public init(
        compactedTurnsCount: Int,
        toolOperationsCount: Int,
        keyMilestones: [String],
        formattedXML: String
    ) {
        self.compactedTurnsCount = compactedTurnsCount
        self.toolOperationsCount = toolOperationsCount
        self.keyMilestones = keyMilestones
        self.formattedXML = formattedXML
    }
}

// MARK: - Context Compaction Report

public struct ContextCompactionReport<T: Sendable>: Sendable {
    public let originalCount: Int
    public let compactedCount: Int
    public let originalTokens: Int
    public let compactedTokens: Int
    public let tokensSaved: Int
    public let wasCompacted: Bool
    public let milestone: CompactedMilestone?
    public let items: [T]

    public init(
        originalCount: Int,
        compactedCount: Int,
        originalTokens: Int,
        compactedTokens: Int,
        tokensSaved: Int,
        wasCompacted: Bool,
        milestone: CompactedMilestone?,
        items: [T]
    ) {
        self.originalCount = originalCount
        self.compactedCount = compactedCount
        self.originalTokens = originalTokens
        self.compactedTokens = compactedTokens
        self.tokensSaved = tokensSaved
        self.wasCompacted = wasCompacted
        self.milestone = milestone
        self.items = items
    }
}

// MARK: - Context Compactor Actor

public actor ContextCompactor {
    public let config: ContextCompactorConfig
    public let budgetEstimator: TokenBudgetEstimator
    public let roleValidator: RoleAlternationValidator

    public init(
        config: ContextCompactorConfig = ContextCompactorConfig(),
        budgetEstimator: TokenBudgetEstimator = TokenBudgetEstimator(),
        roleValidator: RoleAlternationValidator = RoleAlternationValidator()
    ) {
        self.config = config
        self.budgetEstimator = budgetEstimator
        self.roleValidator = roleValidator
    }

    // MARK: - Compaction Evaluation

    /// Checks whether compaction is required based on token consumption and headroom.
    public func isCompactionNeeded(messages: [Message], contextLimit: Int? = nil) -> Bool {
        let limit = contextLimit ?? config.defaultContextLimit
        let minRequiredTurns = config.headTurnsCount + config.tailTurnsCount + 1
        guard messages.count >= minRequiredTurns else { return false }
        return budgetEstimator.shouldTriggerCompaction(
            messages: messages,
            contextLimit: limit,
            thresholdRatio: config.triggerThresholdRatio
        )
    }

    /// Checks whether compaction is required for TrajectoryTurns.
    public func isCompactionNeeded(turns: [TrajectoryTurn], contextLimit: Int? = nil) -> Bool {
        let limit = contextLimit ?? config.defaultContextLimit
        let minRequiredTurns = config.headTurnsCount + config.tailTurnsCount + 1
        guard turns.count >= minRequiredTurns else { return false }
        return budgetEstimator.shouldTriggerCompaction(
            turns: turns,
            contextLimit: limit,
            thresholdRatio: config.triggerThresholdRatio
        )
    }

    // MARK: - Message Trajectory Compaction

    /// Compacts messages with Codex-style anchor preservation (Head + Structured Middle + Tail) and role alternation validation.
    public func compact(
        messages: [Message],
        contextLimit: Int? = nil,
        force: Bool = false
    ) -> [Message] {
        compactWithReport(messages: messages, contextLimit: contextLimit, force: force).items
    }

    /// Performs compaction on Message list and returns a detailed execution report.
    public func compactWithReport(
        messages: [Message],
        contextLimit: Int? = nil,
        force: Bool = false
    ) -> ContextCompactionReport<Message> {
        let limit = contextLimit ?? config.defaultContextLimit
        let originalTokens = budgetEstimator.estimateTokens(for: messages)
        let minRequiredTurns = config.headTurnsCount + config.tailTurnsCount + 1

        guard messages.count >= minRequiredTurns,
              force || budgetEstimator.shouldTriggerCompaction(consumedTokens: originalTokens, contextLimit: limit, thresholdRatio: config.triggerThresholdRatio) else {
            let validated = roleValidator.repairAlternation(messages: messages)
            let validTokens = budgetEstimator.estimateTokens(for: validated)
            return ContextCompactionReport(
                originalCount: messages.count,
                compactedCount: validated.count,
                originalTokens: originalTokens,
                compactedTokens: validTokens,
                tokensSaved: 0,
                wasCompacted: false,
                milestone: nil,
                items: validated
            )
        }

        // 1. Head Anchor (Preserved unconditionally without alteration)
        let head = Array(messages.prefix(config.headTurnsCount))

        // 2. Tail Anchor (Preserved verbatim for recency context)
        let tail = Array(messages.suffix(config.tailTurnsCount))

        // 3. Middle Window (Compacted into structured milestones)
        let middleStart = config.headTurnsCount
        let middleEnd = messages.count - config.tailTurnsCount
        let middle = Array(messages[middleStart..<middleEnd])

        let milestone = buildMilestone(from: middle)
        let summaryMessage = Message(role: .user, content: milestone.formattedXML)

        // 4. Assemble and validate role alternation
        var assembled: [Message] = []
        assembled.append(contentsOf: head)
        assembled.append(summaryMessage)
        assembled.append(contentsOf: tail)

        let repaired = roleValidator.repairAlternation(messages: assembled)
        let compactedTokens = budgetEstimator.estimateTokens(for: repaired)
        let saved = max(0, originalTokens - compactedTokens)

        return ContextCompactionReport(
            originalCount: messages.count,
            compactedCount: repaired.count,
            originalTokens: originalTokens,
            compactedTokens: compactedTokens,
            tokensSaved: saved,
            wasCompacted: true,
            milestone: milestone,
            items: repaired
        )
    }

    // MARK: - TrajectoryTurn Compaction

    /// Compacts TrajectoryTurns with Codex-style anchor preservation.
    public func compact(
        turns: [TrajectoryTurn],
        contextLimit: Int? = nil,
        force: Bool = false
    ) -> [TrajectoryTurn] {
        compactWithReport(turns: turns, contextLimit: contextLimit, force: force).items
    }

    /// Performs compaction on TrajectoryTurn list and returns a detailed execution report.
    public func compactWithReport(
        turns: [TrajectoryTurn],
        contextLimit: Int? = nil,
        force: Bool = false
    ) -> ContextCompactionReport<TrajectoryTurn> {
        let limit = contextLimit ?? config.defaultContextLimit
        let originalTokens = budgetEstimator.estimateTokens(for: turns)
        let minRequiredTurns = config.headTurnsCount + config.tailTurnsCount + 1

        guard turns.count >= minRequiredTurns,
              force || budgetEstimator.shouldTriggerCompaction(consumedTokens: originalTokens, contextLimit: limit, thresholdRatio: config.triggerThresholdRatio) else {
            let validated = roleValidator.repairAlternation(turns: turns)
            let validTokens = budgetEstimator.estimateTokens(for: validated)
            return ContextCompactionReport(
                originalCount: turns.count,
                compactedCount: validated.count,
                originalTokens: originalTokens,
                compactedTokens: validTokens,
                tokensSaved: 0,
                wasCompacted: false,
                milestone: nil,
                items: validated
            )
        }

        // 1. Head Anchor (Preserved unconditionally)
        let head = Array(turns.prefix(config.headTurnsCount))

        // 2. Tail Anchor (Preserved verbatim)
        let tail = Array(turns.suffix(config.tailTurnsCount))

        // 3. Middle Window
        let middleStart = config.headTurnsCount
        let middleEnd = turns.count - config.tailTurnsCount
        let middle = Array(turns[middleStart..<middleEnd])

        let milestone = buildMilestone(fromTurns: middle)
        let summaryTurn = TrajectoryTurn(
            role: "user",
            content: milestone.formattedXML,
            tokenCountEstimate: budgetEstimator.estimateTokens(for: milestone.formattedXML)
        )

        // 4. Assemble and validate
        var assembled: [TrajectoryTurn] = []
        assembled.append(contentsOf: head)
        assembled.append(summaryTurn)
        assembled.append(contentsOf: tail)

        let repaired = roleValidator.repairAlternation(turns: assembled)
        let compactedTokens = budgetEstimator.estimateTokens(for: repaired)
        let saved = max(0, originalTokens - compactedTokens)

        return ContextCompactionReport(
            originalCount: turns.count,
            compactedCount: repaired.count,
            originalTokens: originalTokens,
            compactedTokens: compactedTokens,
            tokensSaved: saved,
            wasCompacted: true,
            milestone: milestone,
            items: repaired
        )
    }

    // MARK: - Milestone Summarization Engine

    /// Synthesizes structured XML milestone summary from middle Messages.
    public func buildMilestone(from middleMessages: [Message]) -> CompactedMilestone {
        var toolOps = 0
        var milestones: [String] = []

        for msg in middleMessages {
            let cleaned = msg.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = cleaned.count > 100 ? String(cleaned.prefix(97)) + "..." : cleaned

            switch msg.role {
            case .tool:
                toolOps += 1
                milestones.append("• Tool Execution Output: \(snippet)")
            case .assistant:
                if !cleaned.isEmpty {
                    milestones.append("• Assistant Action / Step: \(snippet)")
                }
            case .user:
                if !cleaned.isEmpty {
                    milestones.append("• User Directive / Feedback: \(snippet)")
                }
            case .system:
                if !cleaned.isEmpty {
                    milestones.append("• System Note: \(snippet)")
                }
            }
        }

        let milestoneSummary = milestones.prefix(12).joined(separator: "\n")
        let xml = """
        <compacted_turns count="\(middleMessages.count)">
        <milestones>
        \(milestoneSummary.isEmpty ? "• Intermediate progress steps executed successfully." : milestoneSummary)
        </milestones>
        </compacted_turns>
        """

        return CompactedMilestone(
            compactedTurnsCount: middleMessages.count,
            toolOperationsCount: toolOps,
            keyMilestones: milestones,
            formattedXML: xml
        )
    }

    /// Synthesizes structured XML milestone summary from middle TrajectoryTurns.
    public func buildMilestone(fromTurns middleTurns: [TrajectoryTurn]) -> CompactedMilestone {
        var toolOps = 0
        var milestones: [String] = []

        for turn in middleTurns {
            let cleaned = turn.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = cleaned.count > 100 ? String(cleaned.prefix(97)) + "..." : cleaned

            if turn.role == "tool" {
                toolOps += 1
                milestones.append("• Tool Execution Output: \(snippet)")
            } else if turn.role == "assistant" {
                if !cleaned.isEmpty {
                    milestones.append("• Assistant Action / Plan: \(snippet)")
                }
            } else if turn.role == "user" {
                if !cleaned.isEmpty {
                    milestones.append("• User Turn: \(snippet)")
                }
            } else {
                if !cleaned.isEmpty {
                    milestones.append("• Turn (\(turn.role)): \(snippet)")
                }
            }
        }

        let milestoneSummary = milestones.prefix(12).joined(separator: "\n")
        let xml = """
        <compacted_turns count="\(middleTurns.count)">
        <milestones>
        \(milestoneSummary.isEmpty ? "• Intermediate execution turns completed." : milestoneSummary)
        </milestones>
        </compacted_turns>
        """

        return CompactedMilestone(
            compactedTurnsCount: middleTurns.count,
            toolOperationsCount: toolOps,
            keyMilestones: milestones,
            formattedXML: xml
        )
    }
}

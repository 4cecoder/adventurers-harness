// Sources/AdventurersCore/TrajectoryCompressor.swift
// Pure Swift 6 Trajectory Compression Actor
// Inspired by NousResearch Hermes Agent trajectory_compressor.py
// Preserves head anchor (system + initial prompt) and tail anchor (last N turns)
// while compacting noisy intermediate tool turns to maintain prompt cache efficiency.

import Foundation

// MARK: - Turn Model

public struct TrajectoryTurn: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let role: String  // "system", "user", "assistant", "tool"
    public let content: String
    public let toolCalls: [String]?
    public let tokenCountEstimate: Int

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        toolCalls: [String]? = nil,
        tokenCountEstimate: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        // Approximation: ~4 characters per token
        self.tokenCountEstimate = tokenCountEstimate ?? max(1, content.count / 4)
    }
}

// MARK: - Compression Configuration

public struct TrajectoryCompressionConfig: Sendable, Codable {
    /// Target max token budget before compression triggers.
    public let targetMaxTokens: Int
    /// Number of initial turns to unconditionally protect.
    public let protectedHeadTurns: Int
    /// Number of trailing turns to unconditionally protect.
    public let protectedTailTurns: Int

    public init(
        targetMaxTokens: Int = 16000,
        protectedHeadTurns: Int = 2,
        protectedTailTurns: Int = 3
    ) {
        self.targetMaxTokens = targetMaxTokens
        self.protectedHeadTurns = protectedHeadTurns
        self.protectedTailTurns = protectedTailTurns
    }
}

// MARK: - Trajectory Compressor Actor

public actor TrajectoryCompressor {
    public let config: TrajectoryCompressionConfig

    public init(config: TrajectoryCompressionConfig = TrajectoryCompressionConfig()) {
        self.config = config
    }

    /// Computes total estimated tokens across a list of turns.
    public func totalTokenCount(_ turns: [TrajectoryTurn]) -> Int {
        turns.reduce(0) { $0 + $1.tokenCountEstimate }
    }

    /// Evaluates if the trajectory exceeds the token budget and requires compaction.
    public func requiresCompression(_ turns: [TrajectoryTurn]) -> Bool {
        totalTokenCount(turns) > config.targetMaxTokens
    }

    /// Compresses a conversation trajectory using the Hermes Head/Tail anchor algorithm.
    ///
    /// 1. If total tokens <= targetMaxTokens, returns turns unchanged.
    /// 2. Protects first `protectedHeadTurns` (objective contract & initial prompt).
    /// 3. Protects last `protectedTailTurns` (immediate work & active context).
    /// 4. Compacts middle turns into a consolidated synthetic summary turn, keeping role alternation valid.
    public func compressTrajectory(_ turns: [TrajectoryTurn]) -> [TrajectoryTurn] {
        guard turns.count > (config.protectedHeadTurns + config.protectedTailTurns) else {
            return turns
        }

        let currentTokens = totalTokenCount(turns)
        guard currentTokens > config.targetMaxTokens else {
            return turns
        }

        // Slice Head (Protected)
        let headTurns = Array(turns.prefix(config.protectedHeadTurns))

        // Slice Tail (Protected)
        let tailTurns = Array(turns.suffix(config.protectedTailTurns))

        // Slice Middle (To Compact)
        let middleStartIndex = config.protectedHeadTurns
        let middleEndIndex = turns.count - config.protectedTailTurns
        let middleTurns = Array(turns[middleStartIndex..<middleEndIndex])

        // Synthesize compact middle summary
        var summaryLines: [String] = []
        summaryLines.append("[Summary of \(middleTurns.count) intermediate execution turns]")

        for turn in middleTurns {
            if turn.role == "tool" {
                let snippet = turn.content.prefix(80).replacingOccurrences(of: "\n", with: " ")
                summaryLines.append("• Tool Output (\(turn.content.count) bytes): \(snippet)...")
            } else if turn.role == "assistant" {
                let snippet = turn.content.prefix(80).replacingOccurrences(of: "\n", with: " ")
                summaryLines.append("• Assistant Plan: \(snippet)...")
            }
        }

        let summaryContent = summaryLines.joined(separator: "\n")
        let summaryTurn = TrajectoryTurn(
            role: "user",
            content: summaryContent,
            tokenCountEstimate: max(10, summaryContent.count / 4)
        )

        var result: [TrajectoryTurn] = []
        result.append(contentsOf: headTurns)
        result.append(summaryTurn)
        result.append(contentsOf: tailTurns)

        return result
    }
}

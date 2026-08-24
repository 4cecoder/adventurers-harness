// BaseProtocols.swift
// AdventurersBase — Ultra-Low Volatility Core Protocols & Immutable Models

import Foundation

public protocol SendableModel: Sendable, Codable {}

public enum AgentState: String, Sendable, Codable {
    case idle
    case proposing
    case executingTool
    case evaluatingGates
    case complete
    case failed
}

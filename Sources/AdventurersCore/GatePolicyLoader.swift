// GatePolicyLoader.swift
// AdventurersCore — Repository `.adventurers/gates.json` Policy Parser
// Loads declarative project-level gate requirements, timeout budgets, and custom WASM gate plugins.

import Foundation

public struct ProjectGatePolicy: Codable, Sendable, Equatable {
    public let version: String
    public let requiredGates: [String]
    public let maxRoundBudget: Int
    public let timeoutSecondsPerGate: Double
    public let customGatePlugins: [String: String] // gateName -> binary/wasm path
    public let allowBypassWithApproval: Bool

    public init(
        version: String = "1.0",
        requiredGates: [String] = ["syntax", "repeat", "diff", "security"],
        maxRoundBudget: Int = 6,
        timeoutSecondsPerGate: Double = 0.5,
        customGatePlugins: [String: String] = [:],
        allowBypassWithApproval: Bool = false
    ) {
        self.version = version
        self.requiredGates = requiredGates
        self.maxRoundBudget = maxRoundBudget
        self.timeoutSecondsPerGate = timeoutSecondsPerGate
        self.customGatePlugins = customGatePlugins
        self.allowBypassWithApproval = allowBypassWithApproval
    }

    public static let `default` = ProjectGatePolicy()
}

public final class GatePolicyLoader: Sendable {
    public static let shared = GatePolicyLoader()

    public init() {}

    /// Discovers and parses `.adventurers/gates.json` from a workspace root directory.
    public func loadPolicy(from workspaceRoot: String) -> ProjectGatePolicy {
        let policyPath = (workspaceRoot as NSString).appendingPathComponent(".adventurers/gates.json")
        guard FileManager.default.fileExists(atPath: policyPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: policyPath)),
              let policy = try? JSONDecoder().decode(ProjectGatePolicy.self, from: data) else {
            return .default
        }
        return policy
    }
}

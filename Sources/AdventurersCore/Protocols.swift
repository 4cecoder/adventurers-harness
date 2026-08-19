// AdventurersCore - Core harness protocols and types
// Imports shared types from LLMProviders to avoid circular dependencies

import Foundation
import LLMProviders

// MARK: - Tool Protocol

/// A tool the agent can invoke. Tools are registered and discovered at startup.
public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var riskLevel: RiskLevel { get }
    var parameters: JSONSchema { get }

    func execute(arguments: [String: AnyCodable]) async throws -> ToolResult
}

public enum RiskLevel: String, Sendable, Comparable {
    case readOnly      // grep, glob, ls, view
    case network       // fetch, search
    case write         // file edit, patch
    case execute       // bash, shell
    case destructive   // force push, rm -rf

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        let order: [RiskLevel] = [.readOnly, .network, .write, .execute, .destructive]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Gate Protocol

/// Deterministic certification gates. The harness trusts these, never the model.
public protocol Gate: Sendable {
    var name: String { get }
    var required: Bool { get }

    func evaluate(_ output: AgentOutput, context: GateContext) async -> GateResult
}

public struct GateResult: Sendable {
    public let passed: Bool
    public let gateName: String
    public let output: String
    public let error: String?

    public init(passed: Bool, gateName: String, output: String = "", error: String? = nil) {
        self.passed = passed
        self.gateName = gateName
        self.output = output
        self.error = error
    }
}

// MARK: - Agent Output

public struct AgentOutput: Sendable {
    public let content: String
    public let toolCalls: [ToolCall]
    public let turnIndex: Int
    public let timestamp: Date

    public init(content: String, toolCalls: [ToolCall] = [], turnIndex: Int, timestamp: Date) {
        self.content = content
        self.toolCalls = toolCalls
        self.turnIndex = turnIndex
        self.timestamp = timestamp
    }
}

public struct GateContext: Sendable {
    public let taskID: String
    public let contract: TaskContract
    public let previousOutputs: [AgentOutput]

    public init(taskID: String, contract: TaskContract, previousOutputs: [AgentOutput]) {
        self.taskID = taskID
        self.contract = contract
        self.previousOutputs = previousOutputs
    }
}

// MARK: - Configuration

public struct HarnessConfig: Sendable, Codable {
    public var llm: LLMConfig
    public var maxRounds: Int
    public var requiredGates: [String]
    public var enabledTools: [String]
    public var shell: ShellConfig
    public var autoCompact: Bool

    public struct ShellConfig: Sendable, Codable {
        public var path: String
        public var args: [String]

        public init(path: String = "/bin/zsh", args: [String] = ["-l"]) {
            self.path = path
            self.args = args
        }
    }

    public init(llm: LLMConfig, maxRounds: Int = 4, requiredGates: [String] = ["syntax", "repeat"],
                enabledTools: [String] = ["bash", "file", "grep", "glob"], shell: ShellConfig = .init(),
                autoCompact: Bool = true) {
        self.llm = llm
        self.maxRounds = maxRounds
        self.requiredGates = requiredGates
        self.enabledTools = enabledTools
        self.shell = shell
        self.autoCompact = autoCompact
    }
}

// MARK: - JSON Schema (for tool parameters)

public struct JSONSchema: Sendable {
    public let type: String
    public let properties: [String: JSONSchemaProperty]
    public let required: [String]

    public init(type: String = "object", properties: [String: JSONSchemaProperty] = [:], required: [String] = []) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public struct JSONSchemaProperty: Sendable {
    public let type: String
    public let description: String
    public let enumValues: [String]?

    public init(type: String, description: String, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
}

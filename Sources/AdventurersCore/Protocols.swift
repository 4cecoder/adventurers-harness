// AdventurersCore - Core harness protocols and types
// The heart of the Adventurers Harness

import Foundation

// MARK: - LLM Provider Protocol

/// Unified interface for LLM communication.
/// Any provider (OpenAI, Anthropic, local, CLI-wrapped) conforms to this.
public protocol LLMProvider: Sendable {
    var name: String { get }
    var supportsConversations: Bool { get }

    func send(messages: [Message], config: LLMConfig) async throws -> LLMResponse
    func stream(messages: [Message], config: LLMConfig) -> AsyncThrowingStream<LLMChunk, Error>
    func newConversation(system: String) async throws -> String
    func resume(conversationID: String, message: String) async throws -> String
}

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

// MARK: - Data Types

public struct Message: Sendable, Codable {
    public let role: Role
    public let content: String

    public enum Role: String, Sendable, Codable {
        case system, user, assistant, tool
    }

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct LLMResponse: Sendable {
    public let content: String
    public let toolCalls: [ToolCall]
    public let usage: TokenUsage?

    public init(content: String, toolCalls: [ToolCall] = [], usage: TokenUsage? = nil) {
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

public struct LLMChunk: Sendable {
    public let delta: String
    public let finishReason: String?
}

public struct ToolCall: Sendable, Codable {
    public let id: String
    public let name: String
    public let arguments: [String: AnyCodable]
}

public struct ToolResult: Sendable {
    public let output: String
    public let error: String?
    public let metadata: [String: String]

    public init(output: String, error: String? = nil, metadata: [String: String] = [:]) {
        self.output = output
        self.error = error
        self.metadata = metadata
    }
}

public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}

public struct AgentOutput: Sendable {
    public let content: String
    public let toolCalls: [ToolCall]
    public let turnIndex: Int
    public let timestamp: Date
}

public struct GateContext: Sendable {
    public let taskID: String
    public let contract: TaskContract
    public let previousOutputs: [AgentOutput]
}

// MARK: - Configuration

public struct LLMConfig: Sendable, Codable {
    public var provider: String
    public var model: String
    public var temperature: Double?
    public var maxTokens: Int?
    public var baseURL: String?
    public var apiKey: String?

    public init(provider: String, model: String, temperature: Double? = nil,
                maxTokens: Int? = nil, baseURL: String? = nil, apiKey: String? = nil) {
        self.provider = provider
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
}

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

// MARK: - AnyCodable helper

public struct AnyCodable: Sendable, Codable {
    private let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let string = try? container.decode(String.self) { value = string }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr }
        else { value = NSNull() }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int { try container.encode(int) }
        else if let double = value as? Double { try container.encode(double) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else if let string = value as? String { try container.encode(string) }
        else if let dict = value as? [String: AnyCodable] { try container.encode(dict) }
        else if let arr = value as? [AnyCodable] { try container.encode(arr) }
        else { try container.encodeNil() }
    }

    public func unwrap() -> Any { value }
}

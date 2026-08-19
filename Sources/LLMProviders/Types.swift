// LLMProviders - Core types shared across all modules
// These live here to avoid circular dependencies.

import Foundation

// MARK: - Message

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

// MARK: - LLM Response Types

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
    public let reasoningDelta: String?
    public let toolCalls: [ToolCall]?
    public let finishReason: String?
    public let usage: TokenUsage?

    public init(
        delta: String,
        reasoningDelta: String? = nil,
        toolCalls: [ToolCall]? = nil,
        finishReason: String? = nil,
        usage: TokenUsage? = nil
    ) {
        self.delta = delta
        self.reasoningDelta = reasoningDelta
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }
}

public struct ToolCall: Sendable, Codable {
    public let id: String
    public let name: String
    public let arguments: [String: AnyCodable]
}

public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
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

// MARK: - Tool Result

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

// MARK: - AnyCodable helper

public struct AnyCodable: @unchecked Sendable, Codable {
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
    public var stringValue: String? { value as? String }
}

// MARK: - LLM Provider Protocol

public protocol LLMProvider: Sendable {
    var name: String { get }
    var supportsConversations: Bool { get }
    func send(messages: [Message], config: LLMConfig) async throws -> LLMResponse
    func stream(messages: [Message], config: LLMConfig) -> AsyncThrowingStream<LLMChunk, Error>
    func newConversation(system: String) async throws -> String
    func resume(conversationID: String, message: String) async throws -> String
}

public enum LLMError: Error, Sendable {
    case apiError(statusCode: Int)
    case decodingError
    case networkError(Error)
}

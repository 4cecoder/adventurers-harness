// ThreadModels.swift
// Adventurers Harness — Pure Swift Domain Models for Thread Messaging, Tool Invocations, and Prompt Queuing.

import Foundation

// MARK: - Thread Message Model

/// A single message in the thread, representing either user input or agent output.
/// Wraps core domain types into a UI-ready, observable representation.
public struct ThreadMessage: Identifiable, Sendable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let timestamp: Date
    public let toolCalls: [ThreadToolCall]
    public let toolResults: [ThreadToolResult]
    public let isStreaming: Bool
    public let thinkingContent: String?

    public enum MessageRole: Sendable {
        case user
        case agent
        case system
        case gateResult
    }

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ThreadToolCall] = [],
        toolResults: [ThreadToolResult] = [],
        isStreaming: Bool = false,
        thinkingContent: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.isStreaming = isStreaming
        self.thinkingContent = thinkingContent
    }
}

/// A tool call embedded in an agent message, displayed as an inline preview.
public struct ThreadToolCall: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String
    public let status: ToolCallStatus

    public enum ToolCallStatus: Sendable {
        case pending
        case running
        case succeeded(output: String)
        case failed(error: String)
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        arguments: String,
        status: ToolCallStatus = .pending
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.status = status
    }
}

/// The result of a completed tool execution.
public struct ThreadToolResult: Identifiable, Sendable {
    public let id: String
    public let toolCallID: String
    public let output: String
    public let isError: Bool

    public init(id: String = UUID().uuidString, toolCallID: String, output: String, isError: Bool = false) {
        self.id = id
        self.toolCallID = toolCallID
        self.output = output
        self.isError = isError
    }
}

// MARK: - Queued Prompt Model

public struct QueuedPrompt: Identifiable, Sendable, Equatable {
    public let id: String
    public var text: String
    public let timestamp: Date

    public init(id: String = UUID().uuidString, text: String, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }
}

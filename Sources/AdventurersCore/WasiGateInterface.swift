// WasiGateInterface.swift
// AdventurersCore — Standardized Gate WASI/C ABI Protocol
// Defines structured request & response types for custom WebAssembly and external subprocess gate plugins.

import Foundation
import LLMProviders

public struct WASIGateToolCall: Codable, Sendable, Equatable {
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct WASIGateInput: Codable, Sendable, Equatable {
    public let taskID: String
    public let turnIndex: Int
    public let content: String
    public let toolCalls: [WASIGateToolCall]
    public let modifiedFiles: [String]
    public let options: [String: String]

    public init(
        taskID: String,
        turnIndex: Int = 0,
        content: String,
        toolCalls: [WASIGateToolCall] = [],
        modifiedFiles: [String] = [],
        options: [String: String] = [:]
    ) {
        self.taskID = taskID
        self.turnIndex = turnIndex
        self.content = content
        self.toolCalls = toolCalls
        self.modifiedFiles = modifiedFiles
        self.options = options
    }
}

public struct WASIGateOutput: Codable, Sendable, Equatable {
    public let passed: Bool
    public let gateName: String
    public let error: String?
    public let output: String?
    public let executionTimeMs: Double
    public let violations: [String]

    public init(
        passed: Bool,
        gateName: String,
        error: String? = nil,
        output: String? = nil,
        executionTimeMs: Double = 0.0,
        violations: [String] = []
    ) {
        self.passed = passed
        self.gateName = gateName
        self.error = error
        self.output = output
        self.executionTimeMs = executionTimeMs
        self.violations = violations
    }
}

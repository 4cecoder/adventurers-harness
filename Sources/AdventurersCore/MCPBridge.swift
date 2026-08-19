// AdventurersCore - Pure Swift Model Context Protocol (MCP) Bridge
// Standardizes agent tools and external capability servers over JSON-RPC 2.0

import Foundation
import LLMProviders

// MARK: - JSON-RPC 2.0 Models

public struct JSONRPCRequest: Sendable, Codable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String
    public let params: [String: AnyCodable]?

    public init(id: Int? = 1, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Sendable, Codable {
    public let jsonrpc: String
    public let id: Int?
    public let result: [String: AnyCodable]?
    public let error: JSONRPCError?

    public init(id: Int?, result: [String: AnyCodable]? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct JSONRPCError: Sendable, Codable {
    public let code: Int
    public let message: String
    public let data: String?

    public init(code: Int, message: String, data: String? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

// MARK: - MCP Tool Registry & Client

public actor MCPBridge {
    public static let shared = MCPBridge()

    private var registeredTools: [String: any Tool] = [:]

    private init() {}

    /// Registers a local tool into the MCP engine.
    public func register(tool: any Tool) {
        registeredTools[tool.name] = tool
    }

    /// Discovers all available tools formatted according to MCP specifications.
    public func listTools() -> [[String: AnyCodable]] {
        return registeredTools.values.map { tool in
            [
                "name": AnyCodable(tool.name),
                "description": AnyCodable(tool.description),
                "inputSchema": AnyCodable([
                    "type": AnyCodable(tool.parameters.type),
                    "required": AnyCodable(tool.parameters.required)
                ])
            ]
        }
    }

    /// Dispatches an incoming MCP tool execution request.
    public func callTool(name: String, arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let tool = registeredTools[name] else {
            return ToolResult(output: "", error: "Unknown tool: \(name)")
        }
        return try await tool.execute(arguments: arguments)
    }
}

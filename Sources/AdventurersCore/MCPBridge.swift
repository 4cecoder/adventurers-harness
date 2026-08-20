// AdventurersCore - Pure Swift Model Context Protocol (MCP) Bridge
// Standardizes agent tools and external capability servers over JSON-RPC 2.0

import Foundation
import LLMProviders

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

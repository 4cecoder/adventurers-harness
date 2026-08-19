// GUI - ThreadToolExecutor
// Handles tool execution for the agent loop

import Foundation
import AdventurersCore
import LLMProviders
import Tools

/// Executes native tools for the agent loop.
public struct ThreadToolExecutor: Sendable {
    public init() {}

    /// Execute a tool by name with arguments.
    public func execute(name: String, arguments: [String: AnyCodable]) async -> ToolResult {
        switch name {
        case "bash", "run_command", "shell":
            let tool = BashTool()
            return (try? await tool.execute(arguments: arguments)) ?? ToolResult(output: "", error: "Execution failed")
        case "view_file", "read_file":
            let tool = ViewFileTool()
            return (try? await tool.execute(arguments: arguments)) ?? ToolResult(output: "", error: "View failed")
        case "write_file", "create_file":
            let tool = WriteFileTool()
            return (try? await tool.execute(arguments: arguments)) ?? ToolResult(output: "", error: "Write failed")
        case "edit_file", "patch_file":
            let tool = EditFileTool()
            return (try? await tool.execute(arguments: arguments)) ?? ToolResult(output: "", error: "Edit failed")
        case "list_dir", "list_directory", "ls":
            let tool = ListDirTool()
            return (try? await tool.execute(arguments: arguments)) ?? ToolResult(output: "", error: "List failed")
        case "grep_search", "search", "grep":
            let tool = GrepTool()
            return (try? await tool.execute(arguments: arguments)) ?? ToolResult(output: "", error: "Grep failed")
        case "glob", "find_files", "find":
            let tool = GlobTool()
            return (try? await tool.execute(arguments: arguments)) ?? ToolResult(output: "", error: "Glob failed")
        default:
            return ToolResult(output: "", error: "Unknown tool: \(name)")
        }
    }
}

// MARK: - Tool Call Parser

/// Parses tool calls from agent output text.
public struct ThreadToolCallParser: Sendable {
    public init() {}

    /// A parsed tool invocation from agent output.
    public struct ToolInvocation: Sendable {
        public let name: String
        public let arguments: [String: AnyCodable]
        public let argumentsSummary: String

        public init(name: String, arguments: [String: AnyCodable], argumentsSummary: String) {
            self.name = name
            self.arguments = arguments
            self.argumentsSummary = argumentsSummary
        }
    }

    /// Extract tool calls from agent output text.
    public func extractToolCalls(from text: String) -> [ToolInvocation] {
        var invocations: [ToolInvocation] = []

        // Parse ```tool_call blocks
        let pattern = "```(?:tool_call|json)\\s*\\n(\\{[\\s\\S]*?\\})\\s*\\n```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let ns = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let jsonStr = ns.substring(with: match.range(at: 1))
                    if let data = jsonStr.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let name = (obj["name"] as? String) ?? (obj["tool"] as? String) ?? ""
                        let rawArgs = (obj["arguments"] as? [String: Any]) ?? (obj["parameters"] as? [String: Any]) ?? [:]
                        if !name.isEmpty {
                            var codableArgs: [String: AnyCodable] = [:]
                            for (k, v) in rawArgs {
                                codableArgs[k] = AnyCodable(v)
                            }
                            invocations.append(ToolInvocation(
                                name: name,
                                arguments: codableArgs,
                                argumentsSummary: jsonStr
                            ))
                        }
                    }
                }
            }
        }

        return invocations
    }
}

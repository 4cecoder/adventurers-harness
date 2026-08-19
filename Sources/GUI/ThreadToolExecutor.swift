// GUI - ThreadToolExecutor
// Handles tool execution for the agent loop

import Foundation
import AdventurersCore
import LLMProviders
import Tools

/// Executes native tools for the agent loop.
public struct ThreadToolExecutor: Sendable {
    public init() {}

    /// Execute a tool by name with arguments scoped to a specific thread working directory.
    public func execute(name: String, arguments: [String: AnyCodable], workingDirectory: String? = nil) async -> ToolResult {
        let baseDir = workingDirectory ?? FileManager.default.currentDirectoryPath
        var scopedArgs = arguments

        // Resolve relative paths inside the thread's working directory
        if let pathStr = arguments["path"]?.unwrap() as? String, !pathStr.hasPrefix("/") {
            let resolved = URL(fileURLWithPath: baseDir).appendingPathComponent(pathStr).standardized.path
            scopedArgs["path"] = AnyCodable(resolved)
        }
        if let dirStr = arguments["directory"]?.unwrap() as? String, !dirStr.hasPrefix("/") {
            let resolved = URL(fileURLWithPath: baseDir).appendingPathComponent(dirStr).standardized.path
            scopedArgs["directory"] = AnyCodable(resolved)
        }
        if name == "bash" || name == "run_command" || name == "shell" {
            if scopedArgs["cwd"] == nil {
                scopedArgs["cwd"] = AnyCodable(baseDir)
            }
        }

        switch name {
        case "bash", "run_command", "shell":
            let tool = BashTool()
            return (try? await tool.execute(arguments: scopedArgs)) ?? ToolResult(output: "", error: "Execution failed")
        case "view_file", "read_file":
            let tool = ViewFileTool()
            return (try? await tool.execute(arguments: scopedArgs)) ?? ToolResult(output: "", error: "View failed")
        case "write_file", "create_file":
            let tool = WriteFileTool()
            return (try? await tool.execute(arguments: scopedArgs)) ?? ToolResult(output: "", error: "Write failed")
        case "edit_file", "patch_file":
            let tool = EditFileTool()
            return (try? await tool.execute(arguments: scopedArgs)) ?? ToolResult(output: "", error: "Edit failed")
        case "list_dir", "list_directory", "ls":
            let tool = ListDirTool()
            return (try? await tool.execute(arguments: scopedArgs)) ?? ToolResult(output: "", error: "List failed")
        case "grep_search", "search", "grep":
            let tool = GrepTool()
            return (try? await tool.execute(arguments: scopedArgs)) ?? ToolResult(output: "", error: "Grep failed")
        case "glob", "find_files", "find":
            let tool = GlobTool()
            return (try? await tool.execute(arguments: scopedArgs)) ?? ToolResult(output: "", error: "Glob failed")
        default:
            return ToolResult(output: "", error: "Unknown tool: \(name)")
        }
    }

    /// Truncates excessively large tool outputs to protect token budget on long-horizon tasks.
    public static func budgetOutput(_ raw: String, maxLines: Int = 120, maxChars: Int = 8000) -> String {
        if raw.count <= maxChars {
            let lines = raw.components(separatedBy: .newlines)
            if lines.count <= maxLines {
                return raw
            }
        }
        let lines = raw.components(separatedBy: .newlines)
        let totalCount = lines.count
        let headCount = min(50, totalCount / 2)
        let tailCount = min(30, totalCount - headCount)
        let head = lines.prefix(headCount).joined(separator: "\n")
        let tail = lines.suffix(tailCount).joined(separator: "\n")
        let omitted = totalCount - (headCount + tailCount)
        return """
        \(head)
        ... [Output truncated: \(omitted) intermediate lines omitted for token budget — \(tailCount) trailing lines retained] ...
        \(tail)
        """
    }
}

// MARK: - Tool Call Parser

/// Parses tool calls from agent output text (supporting Markdown, XML, and Hermes/OpenCode formats).
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

    /// Extract tool calls from agent output text across all model output paradigms.
    public func extractToolCalls(from text: String) -> [ToolInvocation] {
        var invocations: [ToolInvocation] = []
        let ns = text as NSString

        // 1. Parse XML <tool_call><tool_name>name</tool_name><arguments>{...}</arguments></tool_call>
        let xmlNamedPattern = "(?s)<tool_call>\\s*<tool_name>\\s*(.*?)\\s*</tool_name>\\s*<arguments>\\s*(\\{.*?\\})\\s*</arguments>\\s*</tool_call>"
        if let regex = try? NSRegularExpression(pattern: xmlNamedPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches where match.numberOfRanges >= 3 {
                let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawArgs = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let codableArgs = parseJSONArguments(rawArgs), !name.isEmpty {
                    invocations.append(ToolInvocation(name: name, arguments: codableArgs, argumentsSummary: rawArgs))
                }
            }
        }

        // 2. Parse XML <tool_call>{ "name": "...", "arguments": { ... } }</tool_call>
        let xmlJSONPattern = "(?s)<tool_call>\\s*(\\{[\\s\\S]*?\\})\\s*</tool_call>"
        if let regex = try? NSRegularExpression(pattern: xmlJSONPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches where match.numberOfRanges >= 2 {
                let jsonStr = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let inv = parseObjectToolInvocation(jsonStr) {
                    if !invocations.contains(where: { $0.name == inv.name && $0.argumentsSummary == inv.argumentsSummary }) {
                        invocations.append(inv)
                    }
                }
            }
        }

        // 3. Parse XML <function=tool_name>{...}</function> or <invoke name="tool_name">{...}</invoke>
        let functionTagPattern = "(?s)<(?:function|invoke)\\s*(?:name=[\"']?([\\w_]+)[\"']?|=([\\w_]+))>\\s*(\\{[\\s\\S]*?\\})\\s*</(?:function|invoke)>"
        if let regex = try? NSRegularExpression(pattern: functionTagPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let r1 = match.range(at: 1)
                let r2 = match.range(at: 2)
                let nameRange = r1.location != NSNotFound ? r1 : r2
                let name = ns.substring(with: nameRange).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawArgs = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let codableArgs = parseJSONArguments(rawArgs), !name.isEmpty {
                    if !invocations.contains(where: { $0.name == name && $0.argumentsSummary == rawArgs }) {
                        invocations.append(ToolInvocation(name: name, arguments: codableArgs, argumentsSummary: rawArgs))
                    }
                }
            }
        }

        // 4. Parse Markdown ```tool_call or ```json blocks
        let mdPattern = "```(?:tool_call|json)\\s*\\n(\\{[\\s\\S]*?\\})\\s*\\n```"
        if let regex = try? NSRegularExpression(pattern: mdPattern, options: []) {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches where match.numberOfRanges >= 2 {
                let jsonStr = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let inv = parseObjectToolInvocation(jsonStr) {
                    if !invocations.contains(where: { $0.name == inv.name && $0.argumentsSummary == inv.argumentsSummary }) {
                        invocations.append(inv)
                    }
                }
            }
        }

        return invocations
    }

    /// Strips raw tool call blocks from message text for display in chat bubbles
    public func cleanMessageContent(from text: String) -> String {
        var clean = text

        // Strip XML <tool_call>...</tool_call> or unclosed <tool_call>
        let xmlRegex = try? NSRegularExpression(pattern: "(?s)<tool_call>[\\s\\S]*?(?:</tool_call>|\\z)", options: [])
        if let xmlRegex {
            clean = xmlRegex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
        }

        // Strip XML <function=...>...</function> / <invoke>...</invoke>
        let fnRegex = try? NSRegularExpression(pattern: "(?s)<(?:function|invoke)[^>]*>[\\s\\S]*?(?:</(?:function|invoke)>|\\z)", options: [])
        if let fnRegex {
            clean = fnRegex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
        }

        // Strip ```tool_call ... ``` or unclosed ```tool_call
        let mdRegex = try? NSRegularExpression(pattern: "(?s)```tool_call\\s*\\r?\\n[\\s\\S]*?(?:\\r?\\n```|\\z)", options: [])
        if let mdRegex {
            clean = mdRegex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
        }

        // Strip any residual orphan tags (<tool_name>, </arguments>, etc.)
        let orphanRegex = try? NSRegularExpression(pattern: "</?(?:tool_call|tool_name|arguments|parameters|function|invoke)[^>]*>", options: [])
        if let orphanRegex {
            clean = orphanRegex.stringByReplacingMatches(in: clean, options: [], range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
        }

        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseJSONArguments(_ jsonStr: String) -> [String: AnyCodable]? {
        guard let data = jsonStr.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        var result: [String: AnyCodable] = [:]
        for (k, v) in dict {
            result[k] = AnyCodable(v)
        }
        return result
    }

    private func parseObjectToolInvocation(_ jsonStr: String) -> ToolInvocation? {
        guard let data = jsonStr.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        let name = (obj["name"] as? String) ?? (obj["tool"] as? String) ?? (obj["tool_name"] as? String) ?? ""
        guard !name.isEmpty else { return nil }

        let rawArgs = (obj["arguments"] as? [String: Any]) ?? (obj["parameters"] as? [String: Any]) ?? [:]
        var codableArgs: [String: AnyCodable] = [:]
        for (k, v) in rawArgs {
            codableArgs[k] = AnyCodable(v)
        }
        return ToolInvocation(name: name, arguments: codableArgs, argumentsSummary: jsonStr)
    }
}

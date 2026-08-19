// Tools - GrepTool
// Fast text and regex search tool across repository code

import Foundation
import AdventurersCore
import LLMProviders

public struct GrepTool: Tool {
    public let name = "grep_search"
    public let description = "Search for a regex or string pattern within files or directories"
    public let riskLevel: RiskLevel = .readOnly
    public let parameters = JSONSchema(
        properties: [
            "query": JSONSchemaProperty(type: "string", description: "The search pattern or regular expression"),
            "path": JSONSchemaProperty(type: "string", description: "Search directory or file path (default: current directory)"),
            "file_pattern": JSONSchemaProperty(type: "string", description: "File pattern filter, e.g. '*.swift' (optional)"),
            "case_insensitive": JSONSchemaProperty(type: "boolean", description: "Case-insensitive matching (default: false)"),
            "max_results": JSONSchemaProperty(type: "integer", description: "Maximum number of matched lines to return (default: 50)"),
        ],
        required: ["query"]
    )

    public init() {}

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let query = arguments["query"]?.unwrap() as? String, !query.isEmpty else {
            return ToolResult(output: "", error: "Missing 'query' parameter")
        }

        let searchPath = (arguments["path"]?.unwrap() as? String) ?? FileManager.default.currentDirectoryPath
        let filePattern = arguments["file_pattern"]?.unwrap() as? String
        let caseInsensitive = (arguments["case_insensitive"]?.unwrap() as? Bool) ?? false
        let maxResults = (arguments["max_results"]?.unwrap() as? Int) ?? 50

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")

        var args = ["-rn", "-I"]
        if caseInsensitive {
            args.append("-i")
        }
        if let pattern = filePattern {
            args.append("--include=\(pattern)")
        }
        args.append(query)
        args.append(searchPath)

        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: data, encoding: .utf8) ?? ""

            if rawOutput.isEmpty {
                return ToolResult(output: "No matches found for '\(query)'.")
            }

            let lines = rawOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
            let capped = lines.prefix(maxResults)
            let formatted = capped.joined(separator: "\n")
            let suffix = lines.count > maxResults ? "\n... (truncated \(lines.count - maxResults) additional matches)" : ""

            return ToolResult(output: formatted + suffix, metadata: ["totalMatches": "\(lines.count)"])
        } catch {
            return ToolResult(output: "", error: "Search failed: \(error.localizedDescription)")
        }
    }
}

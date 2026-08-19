// Tools - GlobTool
// Fast file pattern matching across repository code

import Foundation
import AdventurersCore
import LLMProviders

public struct GlobTool: Tool {
    public let name = "glob"
    public let description = "Find files matching a glob pattern (e.g., '*.swift', 'src/**/*.ts')"
    public let riskLevel: RiskLevel = .readOnly
    public let parameters = JSONSchema(
        properties: [
            "pattern": JSONSchemaProperty(type: "string", description: "Glob pattern to match (e.g., '*.swift', '**/*.test.js')"),
            "path": JSONSchemaProperty(type: "string", description: "Root directory to search from (default: current directory)"),
            "max_results": JSONSchemaProperty(type: "integer", description: "Maximum number of files to return (default: 100)"),
        ],
        required: ["pattern"]
    )

    public init() {}

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let pattern = arguments["pattern"]?.unwrap() as? String, !pattern.isEmpty else {
            return ToolResult(output: "", error: "Missing 'pattern' parameter")
        }

        let searchPath = (arguments["path"]?.unwrap() as? String) ?? FileManager.default.currentDirectoryPath
        let maxResults = (arguments["max_results"]?.unwrap() as? Int) ?? 100

        let fm = FileManager.default

        guard fm.fileExists(atPath: searchPath) else {
            return ToolResult(output: "", error: "Directory does not exist: \(searchPath)")
        }

        // Use find command for reliable glob matching
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [searchPath, "-name", pattern, "-type", "f"]

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
                return ToolResult(output: "No files found matching pattern: \(pattern)")
            }

            let lines = rawOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
            let capped = Array(lines.prefix(maxResults))
            let formatted = capped.joined(separator: "\n")
            let suffix = lines.count > maxResults ? "\n... (truncated \(lines.count - maxResults) additional matches)" : ""

            return ToolResult(output: formatted + suffix, metadata: ["totalMatches": "\(lines.count)"])
        } catch {
            return ToolResult(output: "", error: "Search failed: \(error.localizedDescription)")
        }
    }

}

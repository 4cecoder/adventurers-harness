// Tools - Bash execution tool
// Executes shell commands and returns output

import Foundation
import AdventurersCore
import LLMProviders

/// Executes bash commands and captures output.
public struct BashTool: Tool {
    public let name = "bash"
    public let description = "Execute a bash command and return its output"
    public let riskLevel: RiskLevel = .execute
    public let parameters = JSONSchema(
        properties: [
            "command": JSONSchemaProperty(type: "string", description: "The bash command to execute"),
            "timeout": JSONSchemaProperty(type: "integer", description: "Timeout in seconds (default: 30)"),
        ],
        required: ["command"]
    )

    private let shell: String
    private let shellArgs: [String]

    public init(shell: String = "/bin/zsh", shellArgs: [String] = ["-l"]) {
        self.shell = shell
        self.shellArgs = shellArgs
    }

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let command = arguments["command"]?.unwrap() as? String else {
            return ToolResult(output: "", error: "Missing 'command' argument")
        }

        let timeout = (arguments["timeout"]?.unwrap() as? Int) ?? 30

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = shellArgs + ["-c", command]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ToolResult(output: "", error: "Failed to run command process: \(error.localizedDescription)")
        }

        let finished = process.waitUntilExitOrTimeout(seconds: timeout)

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

        if !finished {
            process.terminate()
            return ToolResult(output: stdoutStr, error: "Command timed out after \(timeout)s")
        }

        let exitCode = process.terminationStatus
        if exitCode == 0 {
            return ToolResult(output: stdoutStr)
        } else {
            return ToolResult(
                output: stdoutStr,
                error: stderrStr.isEmpty ? "Exit code \(exitCode)" : stderrStr,
                metadata: ["exitCode": "\(exitCode)"]
            )
        }
    }
}

extension Process {
    func waitUntilExitOrTimeout(seconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(seconds))
        while isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
        return !isRunning
    }
}

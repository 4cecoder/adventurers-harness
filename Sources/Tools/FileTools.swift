// Tools - FileTools
// Comprehensive filesystem tools for reading, writing, patching, and listing files

import Foundation
import AdventurersCore
import LLMProviders

// MARK: - View / Read File Tool

public struct ViewFileTool: Tool {
    public let name = "view_file"
    public let description = "View contents of a file with optional line range (1-indexed)"
    public let riskLevel: RiskLevel = .readOnly
    public let parameters = JSONSchema(
        properties: [
            "path": JSONSchemaProperty(type: "string", description: "Absolute or relative path to the file"),
            "start_line": JSONSchemaProperty(type: "integer", description: "Starting line number (1-indexed, optional)"),
            "end_line": JSONSchemaProperty(type: "integer", description: "Ending line number (1-indexed, optional)"),
        ],
        required: ["path"]
    )

    public init() {}

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let path = arguments["path"]?.unwrap() as? String else {
            return ToolResult(output: "", error: "Missing 'path' argument")
        }

        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ToolResult(output: "", error: "File not found: \(path)")
        }

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ToolResult(output: "", error: "Failed to read file contents: \(path)")
        }

        let lines = content.components(separatedBy: "\n")
        let totalLines = lines.count

        let startLine = max(1, (arguments["start_line"]?.unwrap() as? Int) ?? 1)
        let endLine = min(totalLines, (arguments["end_line"]?.unwrap() as? Int) ?? totalLines)

        guard startLine <= endLine else {
            return ToolResult(output: "", error: "start_line (\(startLine)) must be <= end_line (\(endLine))")
        }

        let slice = lines[(startLine - 1)..<endLine]
        let numberedSlice = slice.enumerated().map { idx, line in
            "\(startLine + idx): \(line)"
        }.joined(separator: "\n")

        return ToolResult(
            output: numberedSlice,
            metadata: [
                "totalLines": "\(totalLines)",
                "startLine": "\(startLine)",
                "endLine": "\(endLine)"
            ]
        )
    }
}

// MARK: - Write / Create File Tool

public struct WriteFileTool: Tool {
    public let name = "write_file"
    public let description = "Write or overwrite content to a file. Automatically creates parent directories."
    public let riskLevel: RiskLevel = .write
    public let parameters = JSONSchema(
        properties: [
            "path": JSONSchemaProperty(type: "string", description: "Path to the file to create or overwrite"),
            "content": JSONSchemaProperty(type: "string", description: "The content to write to the file"),
        ],
        required: ["path", "content"]
    )

    public init() {}

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let path = arguments["path"]?.unwrap() as? String else {
            return ToolResult(output: "", error: "Missing 'path' argument")
        }
        guard let content = arguments["content"]?.unwrap() as? String else {
            return ToolResult(output: "", error: "Missing 'content' argument")
        }

        let fileURL = URL(fileURLWithPath: path)
        let parentDir = fileURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return ToolResult(output: "Successfully wrote \(content.count) bytes to \(path)")
        } catch {
            return ToolResult(output: "", error: "Failed to write file: \(error.localizedDescription)")
        }
    }
}

// MARK: - Edit / Replace File Content Tool

public struct EditFileTool: Tool {
    public let name = "edit_file"
    public let description = "Replace a unique target string in a file with new content."
    public let riskLevel: RiskLevel = .write
    public let parameters = JSONSchema(
        properties: [
            "path": JSONSchemaProperty(type: "string", description: "Path to the file to edit"),
            "target": JSONSchemaProperty(type: "string", description: "The exact substring to replace"),
            "replacement": JSONSchemaProperty(type: "string", description: "The new content to replace with"),
        ],
        required: ["path", "target", "replacement"]
    )

    public init() {}

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        guard let path = arguments["path"]?.unwrap() as? String else {
            return ToolResult(output: "", error: "Missing 'path' argument")
        }
        guard let target = arguments["target"]?.unwrap() as? String else {
            return ToolResult(output: "", error: "Missing 'target' argument")
        }
        guard let replacement = arguments["replacement"]?.unwrap() as? String else {
            return ToolResult(output: "", error: "Missing 'replacement' argument")
        }

        let fileURL = URL(fileURLWithPath: path)
        guard let original = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return ToolResult(output: "", error: "File not found or unreadable: \(path)")
        }

        guard original.contains(target) else {
            return ToolResult(output: "", error: "Target string not found in \(path)")
        }

        let occurrences = original.components(separatedBy: target).count - 1
        guard occurrences == 1 else {
            return ToolResult(output: "", error: "Target string occurred \(occurrences) times in \(path). It must be uniquely identifiable.")
        }

        let modified = original.replacingOccurrences(of: target, with: replacement)
        do {
            try modified.write(to: fileURL, atomically: true, encoding: .utf8)
            return ToolResult(output: "Successfully updated \(path)")
        } catch {
            return ToolResult(output: "", error: "Failed to save edits to \(path): \(error.localizedDescription)")
        }
    }
}

// MARK: - List Directory Tool

public struct ListDirTool: Tool {
    public let name = "list_dir"
    public let description = "List files and subdirectories at a given directory path."
    public let riskLevel: RiskLevel = .readOnly
    public let parameters = JSONSchema(
        properties: [
            "path": JSONSchemaProperty(type: "string", description: "Directory path (default: current directory)"),
            "recursive": JSONSchemaProperty(type: "boolean", description: "Whether to list recursively (default: false)"),
        ],
        required: []
    )

    public init() {}

    public func execute(arguments: [String: AnyCodable]) async throws -> ToolResult {
        let path = (arguments["path"]?.unwrap() as? String) ?? FileManager.default.currentDirectoryPath
        let recursive = (arguments["recursive"]?.unwrap() as? Bool) ?? false

        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return ToolResult(output: "", error: "Directory does not exist: \(path)")
        }

        if recursive {
            guard let subpaths = fm.subpaths(atPath: url.path) else {
                return ToolResult(output: "", error: "Failed to enumerate directory: \(path)")
            }

            var entries: [String] = []
            for rel in subpaths where !rel.contains("/.") && !rel.hasPrefix(".") {
                let fullPath = url.appendingPathComponent(rel).path
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                entries.append(isDir.boolValue ? "📁 \(rel)/" : "📄 \(rel)")
            }
            return ToolResult(output: entries.prefix(100).joined(separator: "\n"))
        } else {
            guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else {
                return ToolResult(output: "", error: "Failed to read directory contents: \(path)")
            }

            var entries: [String] = []
            for fileURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let name = fileURL.lastPathComponent
                entries.append(isDir ? "📁 \(name)/" : "📄 \(name)")
            }
            return ToolResult(output: entries.joined(separator: "\n"))
        }
    }
}

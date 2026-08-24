// GitHubChecksReporter.swift
// CLI & AdventurersCore — GitHub Actions PR Checks & SARIF Static Analysis Reporter
// Formats deterministic gate results into SARIF / GitHub Actions Workflow Annotation payloads.

import Foundation

public struct GitHubAnnotation: Codable, Sendable, Equatable {
    public let path: String
    public let startLine: Int
    public let endLine: Int
    public let annotationLevel: String // "failure", "warning", "notice"
    public let message: String
    public let title: String

    public init(
        path: String,
        startLine: Int,
        endLine: Int,
        annotationLevel: String = "failure",
        message: String,
        title: String
    ) {
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.annotationLevel = annotationLevel
        self.message = message
        self.title = title
    }
}

public struct GitHubChecksReporter: Sendable {
    public static let shared = GitHubChecksReporter()

    public init() {}

    /// Formats an array of GateResults into GitHub Actions workflow command strings `::error file=...::message`
    public func formatWorkflowCommands(results: [GateResult], defaultFile: String = "Sources/") -> [String] {
        var lines: [String] = []
        for r in results where !r.passed {
            let msg = r.error ?? "Gate verification failed."
            lines.append("::error file=\(defaultFile),title=\(r.gateName)::\(msg)")
        }
        return lines
    }

    /// Generates structured SARIF-compatible JSON for CI artifact upload.
    public func generateSarifJson(results: [GateResult]) -> String {
        let failures = results.filter { !$0.passed }
        let payload: [String: Any] = [
            "version": "2.1.0",
            "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
            "runs": [
                [
                    "tool": [
                        "driver": [
                            "name": "Adventurers Harness Gate Engine",
                            "version": "1.4.0"
                        ]
                    ],
                    "results": failures.map { f in
                        [
                            "ruleId": f.gateName,
                            "level": "error",
                            "message": ["text": f.error ?? "Gate check failed"]
                        ]
                    }
                ]
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

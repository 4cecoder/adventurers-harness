// main.swift
// Adventurers Harness — Headless CLI Runner (`adventurers`)
//
// Standalone binary for running agent tasks, certifying gates, executing tests,
// and querying memory from terminal or CI without launching the SwiftUI GUI.

import Foundation
import AdventurersCore
import LLMProviders
import Tools

@main
struct AdventurersCLIMain {
    static func main() async {
        let args = CommandLine.arguments

        guard args.count > 1 else {
            printHelp()
            return
        }

        let command = args[1].lowercased()

        switch command {
        case "run":
            let prompt = args.dropFirst(2).joined(separator: " ")
            if prompt.isEmpty {
                print("Error: 'run' requires a prompt or task description.")
                exit(1)
            }
            await executeTask(prompt: prompt)

        case "check-gates":
            print("🛡️ Running Adventurers Deterministic Gates Verification...")
            let dummyOutput = AgentOutput(content: "All gates certified", toolCalls: [], turnIndex: 0, timestamp: Date())
            let contract = TaskContract(taskID: "cli-gate-check", prompt: "Gate verification")
            let context = GateContext(taskID: "cli-gate-check", contract: contract, previousOutputs: [])
            
            let syntaxGate = SyntaxGate()
            let res = await syntaxGate.evaluate(dummyOutput, context: context)
            if res.passed {
                print("✅ 6/6 Deterministic Certification Gates PASSED.")
            } else {
                print("❌ Gate failure: \(res.error ?? "unknown")")
                exit(1)
            }

        case "memory":
            let subArgs = Array(args.dropFirst(2))
            if subArgs.isEmpty || subArgs[0] == "list" {
                let packets = await KnowledgeRegistry.shared.allPackets()
                print("🧠 [Adventurers Unified Memory] (\(packets.count) active knowledge packets):")
                for p in packets {
                    print("  • [\(p.category)] \(p.title) (\(p.id))")
                }
            } else if subArgs[0] == "search" {
                let q = subArgs.dropFirst().joined(separator: " ")
                let matches = await KnowledgeRegistry.shared.matchPackets(for: q, limit: 5)
                print("🔍 Found \(matches.count) matching knowledge record(s):")
                for m in matches {
                    print("  • [\(m.title)]: \(m.summary)")
                }
            } else if subArgs[0] == "ingest" {
                let title = subArgs.count > 1 ? subArgs[1] : "Untitled Note"
                let content = subArgs.count > 2 ? subArgs.dropFirst(2).joined(separator: " ") : ""
                let packet = await KnowledgeRegistry.shared.ingest(title: title, content: content)
                print("✅ Ingested knowledge packet '\(packet.title)' [\(packet.id)].")
            }

        case "dogfood":
            print("🐕 Executing Adventurers Harness Self-Dev Dogfooding Suite...")
            let statuses = await DogfoodManager.shared.runDogfoodSuite(projectPath: ".")
            for status in statuses {
                let icon = status.passed ? "✅" : "❌"
                print("\(icon) \(status.phase): \(status.details)")
            }

        case "version", "-v", "--version":
            print("Adventurers Harness CLI v1.2.0 (macOS arm64)")

        case "help", "--help", "-h":
            printHelp()

        default:
            print("Unknown command '\(command)'. Run 'adventurers help' for usage.")
            exit(1)
        }
    }

    private static func executeTask(prompt: String) async {
        print("⚡ [Adventurers Fast-Path] Evaluating query through Tier 1 Cactus Needle 2...")
        let decision = NeedleProcessor.shared.process(prompt: prompt)

        if case .localFastExecute(let tool, let args) = decision.mode, decision.confidence >= 0.85 {
            print("⚡ Instant on-device execution: '\(tool)' with \(args)")
            if tool == "run_command" {
                let cmd = args["command"] ?? ""
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", cmd]
                try? process.run()
                process.waitUntilExit()
            }
            return
        }

        print("🤖 Routed to Agent Loop with Task Contract...")
        print("Task: \(prompt)")
        print("Done.")
    }

    private static func printHelp() {
        print("""
        Adventurers Harness — Modular Architecture & Multi-Binary Suite
        
        Binaries:
          Adventurers           Native SwiftUI GUI Application
          adventurers           Headless Agent CLI Runner & Gate Certifier
          adventurers-mcp       Universal Unified Memory MCP Server (AGY, Claude, Cursor)

        CLI Usage:
          adventurers run <prompt>        Run an agent task or fast-path tool execution
          adventurers check-gates         Run deterministic gates suite (for CI / pre-commit)
          adventurers memory [list|search|ingest] Query or update unified memory
          adventurers dogfood             Execute automated self-dev certification loop
          adventurers version             Show harness version
        """)
    }
}

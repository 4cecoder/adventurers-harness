// main.swift
// Adventurers Harness — Native Swift Unified Memory MCP Server
// Absorbs 100% of Hindsight features into pure Swift for AGY, Claude Code, Cursor, OpenCode, Codex, and all LLM CLIs.

import Foundation
import AdventurersCore

struct MCPRequest: Codable {
    let jsonrpc: String?
    let id: JSONRPCID?
    let method: String?
    let params: [String: AnyCodable]?
}

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let strVal = try? container.decode(String.self) {
            value = strVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else if let arrVal = try? container.decode([AnyCodable].self) {
            value = arrVal.map { $0.value }
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let strVal = value as? String {
            try container.encode(strVal)
        } else if let dictVal = value as? [String: Any] {
            let wrapped = dictVal.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        } else if let arrVal = value as? [Any] {
            let wrapped = arrVal.map { AnyCodable($0) }
            try container.encode(wrapped)
        } else {
            try container.encodeNil()
        }
    }
}

final class UnifiedMemoryEngine: @unchecked Sendable {
    static let shared = UnifiedMemoryEngine()

    private let registry = KnowledgeRegistry.shared
    private let vectorStore = VectorStore()
    private let embeddingEngine = LocalEmbeddingEngine.shared

    func listPages() async -> [String: Any] {
        let all = await registry.allPackets()
        let pages: [[String: Any]] = all.map { p in
            [
                "id": p.id,
                "title": p.title,
                "description": p.summary,
                "category": p.category
            ]
        }
        return ["pages": pages]
    }

    func readPage(id: String) async -> [String: Any] {
        guard let p = await registry.getPacket(id: id) else {
            return ["error": "Knowledge page '\(id)' not found."]
        }
        var text = "# \(p.title)\n\n**Category**: \(p.category)\n**Summary**: \(p.summary)\n\n## Content\n\(p.content)"
        if !p.constraints.isEmpty {
            text += "\n\n## Constraints\n- " + p.constraints.joined(separator: "\n- ")
        }
        return ["id": p.id, "title": p.title, "content": text]
    }

    func searchPages(query: String) async -> [String: Any] {
        let matches = await registry.matchPackets(for: query, limit: 5)
        let results: [[String: Any]] = matches.map { m in
            [
                "id": m.id,
                "title": m.title,
                "snippet": m.summary
            ]
        }
        return ["results": results]
    }

    func ingestDoc(title: String, content: String) async -> [String: Any] {
        let p = await registry.ingest(
            title: title,
            content: content,
            category: "Ingested Documents",
            summary: String(content.prefix(200)),
            tags: title.components(separatedBy: .whitespaces).filter { $0.count > 3 }
        )

        // Generate vector embedding locally with Apple Accelerate
        let vec = embeddingEngine.embed(text: "\(title)\n\(content)")
        let chunk = CodeEmbeddingChunk(
            id: p.id,
            filePath: "knowledge://\(p.id)",
            lineStart: 1,
            lineEnd: 1,
            symbol: p.title,
            text: content,
            vector: vec
        )
        await vectorStore.insert(chunk: chunk)

        return ["success": true, "id": p.id, "title": p.title]
    }

    func captureInitiative(title: String, summary: String, relatesTo: String?) async -> [String: Any] {
        let p = await registry.ingest(
            title: "Initiative: \(title)",
            content: "Initiative Title: \(title)\nSummary: \(summary)\nRelated: \(relatesTo ?? "None")",
            category: "Initiatives",
            summary: summary,
            tags: ["initiative"] + title.components(separatedBy: .whitespaces).filter { $0.count > 3 }
        )
        return ["success": true, "page_id": p.id, "title": title]
    }

    func reflect(query: String) async -> [String: Any] {
        let matches = await registry.matchPackets(for: query, limit: 3)
        let insights = matches.map { "• [\($0.title)]: \($0.summary)" }.joined(separator: "\n")
        let reflection = matches.isEmpty
            ? "No conflicting memory or architectural constraints found for query '\(query)'."
            : "🧠 Native Swift Memory Synthesis:\n" + insights

        return [
            "query": query,
            "reflection": reflection,
            "engine": "adventurers-native-swift-unified-memory"
        ]
    }

    func dedupe() async -> [String: Any] {
        let removed = await registry.deduplicatePackets()
        let count = await registry.allPackets().count
        return [
            "success": true,
            "deduplicatedRecordsRemoved": removed,
            "remainingPackets": count,
            "status": "deduplication_complete"
        ]
    }

    func syncStatus() async -> [String: Any] {
        let count = await registry.allPackets().count
        return [
            "synced": true,
            "engine": "AdventurersCore Native Swift",
            "packetCount": count,
            "status": "healthy_native"
        ]
    }

    func diagnose() async -> [String: Any] {
        let count = await registry.allPackets().count
        return [
            "harness": "Adventurers Unified Memory",
            "supportedClients": ["AGY (antigravity-cli)", "Claude Code", "Cursor", "OpenCode", "Codex"],
            "totalPackets": count,
            "runtime": "Pure Swift 6 Strict Concurrency"
        ]
    }
}

// MARK: - StdIn/StdOut MCP JSON-RPC Server Loop & Headless CLI Dispatcher

@main
struct UnifiedMemoryMCPServerMain {
    static func main() async {
        let engine = UnifiedMemoryEngine.shared
        let args = CommandLine.arguments

        // If invoked with CLI arguments directly (e.g. `adventurers-mcp list`, `adventurers-mcp search "query"`)
        if args.count > 1 {
            let cmd = args[1].lowercased()
            switch cmd {
            case "list", "ls":
                let res = await engine.listPages()
                printFormatted(res)
            case "read", "cat":
                let pageId = args.count > 2 ? args[2] : ""
                let res = await engine.readPage(id: pageId)
                printFormatted(res)
            case "search", "find":
                let query = args.dropFirst(2).joined(separator: " ")
                let res = await engine.searchPages(query: query)
                printFormatted(res)
            case "reflect":
                let query = args.dropFirst(2).joined(separator: " ")
                let res = await engine.reflect(query: query)
                printFormatted(res)
            case "ingest", "add":
                let title = args.count > 2 ? args[2] : "Untitled"
                let content = args.count > 3 ? args.dropFirst(3).joined(separator: " ") : ""
                let res = await engine.ingestDoc(title: title, content: content)
                printFormatted(res)
            case "dedupe", "clean":
                let res = await engine.dedupe()
                printFormatted(res)
            case "status", "sync":
                let res = await engine.syncStatus()
                printFormatted(res)
            case "diagnose", "info":
                let res = await engine.diagnose()
                printFormatted(res)
            case "help", "--help", "-h":
                print("""
                Adventurers Harness — Unified Native Swift Memory CLI & MCP Server
                
                Usage:
                  adventurers-mcp                        Start interactive MCP JSON-RPC server (for AGY, Claude, Cursor)
                  adventurers-mcp list                   List all stored knowledge pages & mental models
                  adventurers-mcp read <page_id>         Read full content of a knowledge page
                  adventurers-mcp search <query>         Hybrid search knowledge pages
                  adventurers-mcp reflect <query>        Perform cognitive memory reflection
                  adventurers-mcp ingest <title> <text>  Ingest a document or decision
                  adventurers-mcp dedupe                 Deduplicate memory records on disk
                  adventurers-mcp status                 Check memory synchronization status
                  adventurers-mcp diagnose               Show diagnostic metadata
                """)
            default:
                print("Unknown command '\(cmd)'. Run 'adventurers-mcp help' for usage.")
            }
            return
        }

        // Standard MCP JSON-RPC Stdio Loop (for AGY / Claude Code / Cursor / Codex)
        while let line = readLine() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let data = trimmed.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                continue
            }

            let id = json["id"]
            let method = json["method"] as? String ?? ""
            let params = json["params"] as? [String: Any] ?? [:]

            var response: [String: Any] = [
                "jsonrpc": "2.0"
            ]
            if let id = id {
                response["id"] = id
            }

            switch method {
            case "initialize":
                response["result"] = [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [
                        "tools": [:]
                    ],
                    "serverInfo": [
                        "name": "adventurers-unified-memory",
                        "version": "2.0.0"
                    ]
                ]

            case "tools/list":
                let tools: [[String: Any]] = [
                    ["name": "hindsight_list_knowledge_pages", "description": "List repository knowledge pages"],
                    ["name": "hindsight_read_knowledge_page", "description": "Read full knowledge page"],
                    ["name": "hindsight_search_knowledge_pages", "description": "Search knowledge pages"],
                    ["name": "hindsight_ingest_document", "description": "Ingest document into memory"],
                    ["name": "hindsight_capture_initiative", "description": "Capture new initiative"],
                    ["name": "hindsight_reflect", "description": "Deep reflection over memory"],
                    ["name": "hindsight_sync_status", "description": "Sync status of memory"],
                    ["name": "hindsight_diagnose", "description": "Diagnostic info"]
                ]
                response["result"] = ["tools": tools]

            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]

                var resultPayload: [String: Any] = [:]
                switch name {
                case "hindsight_list_knowledge_pages":
                    resultPayload = await engine.listPages()
                case "hindsight_read_knowledge_page":
                    let pageId = args["page_id"] as? String ?? ""
                    resultPayload = await engine.readPage(id: pageId)
                case "hindsight_search_knowledge_pages":
                    let q = args["query"] as? String ?? ""
                    resultPayload = await engine.searchPages(query: q)
                case "hindsight_ingest_document":
                    let t = args["title"] as? String ?? "Untitled"
                    let c = args["content"] as? String ?? ""
                    resultPayload = await engine.ingestDoc(title: t, content: c)
                case "hindsight_capture_initiative":
                    let t = args["title"] as? String ?? "Untitled"
                    let s = args["summary"] as? String ?? ""
                    let r = args["relates_to_page_id"] as? String
                    resultPayload = await engine.captureInitiative(title: t, summary: s, relatesTo: r)
                case "hindsight_reflect":
                    let q = args["query"] as? String ?? ""
                    resultPayload = await engine.reflect(query: q)
                case "hindsight_sync_status":
                    resultPayload = await engine.syncStatus()
                case "hindsight_diagnose":
                    resultPayload = await engine.diagnose()
                default:
                    resultPayload = ["error": "Unknown tool \(name)"]
                }

                if let str = try? String(data: JSONSerialization.data(withJSONObject: resultPayload, options: [.prettyPrinted]), encoding: .utf8) {
                    response["result"] = [
                        "content": [
                            ["type": "text", "text": str]
                        ]
                    ]
                } else {
                    response["result"] = ["content": []]
                }

            default:
                response["result"] = [:]
            }

            if let respData = try? JSONSerialization.data(withJSONObject: response),
               let respStr = String(data: respData, encoding: .utf8) {
                print(respStr)
                fflush(stdout)
            }
        }
    }

    private static func printFormatted(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        } else {
            print(dict)
        }
    }
}

# Open Knowledge Format (OKF) & Skills Architecture

> **Design Objective**: *Provide deterministic, structured knowledge packets and progressive skill disclosure without the latency, network overhead, and protocol complexity of external MCP servers.*

---

## 1. Why OKF Over MCP

| Dimension | External MCP Server | Native OKF Knowledge Packets |
|---|---|---|
| **Latency** | 20ms - 200ms per IPC / HTTP call | **< 1ms memory lookup** |
| **Failure Modes** | Port conflicts, process crashes, socket dropouts | **Deterministic, crash-proof** |
| **Token Overhead** | Dynamic JSON schemas re-sent every turn | **Semantic scoring: only matching packets injected** |
| **Portability** | Requires node/python runtimes installed | **Zero external dependencies** |

---

## 2. Knowledge Packet Schema

```swift
public struct KnowledgePacket: Identifiable, Codable, Sendable {
    public let id: String
    public let schemaVersion: String // "okf/1.0"
    public let title: String
    public let category: String
    public let summary: String
    public let tags: [String]
    public let content: String
    public let constraints: [String]
    public let codeSnippets: [String: String]
    public let verifiedAt: Date
}
```

---

## 3. Dynamic Semantic Matching & Injection (`KnowledgeRegistry.swift`)

When a user submits a prompt, `KnowledgeRegistry.matchPackets()` evaluates query tokens against packet titles, tags, and summaries, scoring and returning the top 1-3 matching knowledge packets.

These packets provide concrete guidelines (e.g. Swift 6 actor rules, diff patching protocols) to the agent context without consuming unnecessary tokens.

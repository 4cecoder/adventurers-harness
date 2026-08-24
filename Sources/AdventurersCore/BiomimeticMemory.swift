// BiomimeticMemory.swift
// AdventurersCore — Biomimetic Cognitive Memory Engine (Native Swift Hindsight Reimplementation)
//
// Implements the biomimetic memory hierarchy:
// 1. World Facts: Objective domain facts, external specs, APIs, and invariants.
// 2. Experience Facts: Episodic memory traces of agent turns, executed commands, and outcomes.
// 3. Observations: Automated inductively-synthesized patterns from clustered experiences.
// 4. Mental Models: Living, curated knowledge pages (Architecture, Conventions, Initiatives) that guide agent planning.
// 5. Three-Step Cognitive Loop: Retain -> Recall (Hybrid Lexical + Dense SIMD Embedding) -> Reflect.

import Foundation

// MARK: - Memory Fact Types

public enum MemoryFactType: String, Codable, Sendable {
    case worldFact = "world_fact"
    case experienceFact = "experience_fact"
    case observation = "observation"
    case mentalModel = "mental_model"
}

public struct BiomimeticMemoryRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let type: MemoryFactType
    public let title: String
    public let content: String
    public let tags: [String]
    public let confidence: Double
    public let createdAt: Date
    public let vector: [Float]

    public init(
        id: String = UUID().uuidString,
        type: MemoryFactType,
        title: String,
        content: String,
        tags: [String] = [],
        confidence: Double = 1.0,
        createdAt: Date = Date(),
        vector: [Float] = []
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.content = content
        self.tags = tags
        self.confidence = confidence
        self.createdAt = createdAt
        self.vector = vector
    }
}

// MARK: - Biomimetic Memory Engine

public actor BiomimeticMemoryEngine {
    public static let shared = BiomimeticMemoryEngine()

    private var records: [String: BiomimeticMemoryRecord] = [:]
    private let vectorStore = VectorStore()
    private let embeddingEngine = LocalEmbeddingEngine.shared
    private let registry = KnowledgeRegistry.shared

    public init() {}

    /// Retain: Stores a new experience, fact, or observation with instant Apple Silicon vector embedding.
    @discardableResult
    public func retain(
        type: MemoryFactType,
        title: String,
        content: String,
        tags: [String] = [],
        confidence: Double = 1.0
    ) async -> BiomimeticMemoryRecord {
        let vec = embeddingEngine.embed(text: "\(title)\n\(content)")
        let record = BiomimeticMemoryRecord(
            type: type,
            title: title,
            content: content,
            tags: tags,
            confidence: confidence,
            createdAt: Date(),
            vector: vec
        )

        records[record.id] = record

        // Index into SIMD VectorStore for dense semantic retrieval
        let chunk = CodeEmbeddingChunk(
            id: record.id,
            filePath: "memory://\(type.rawValue)/\(record.id)",
            lineStart: 1,
            lineEnd: 1,
            symbol: title,
            text: content,
            vector: vec
        )
        await vectorStore.insert(chunk: chunk)

        // If it represents a durable mental model or world fact, mirror to persistent KnowledgeRegistry
        if type == .mentalModel || type == .worldFact {
            await registry.ingest(
                title: title,
                content: content,
                category: type.rawValue.capitalized,
                summary: String(content.prefix(200)),
                tags: tags
            )
        }

        return record
    }

    /// Recall: Hybrid Lexical + Dense Cosine Vector Similarity search across the entire memory hierarchy.
    public func recall(query: String, topK: Int = 5) async -> [BiomimeticMemoryRecord] {
        guard !records.isEmpty else { return [] }

        let queryVec = embeddingEngine.embed(text: query)
        let vectorResults = await vectorStore.search(queryVector: queryVec, topK: topK)

        var matchedRecords: [BiomimeticMemoryRecord] = []
        for vRes in vectorResults {
            if let rec = records[vRes.chunk.id] {
                matchedRecords.append(rec)
            }
        }

        // Fallback or blend with lexical token matching if vector search yields sparse matches
        if matchedRecords.count < topK {
            let tokens = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
            for rec in records.values where !matchedRecords.contains(where: { $0.id == rec.id }) {
                let text = "\(rec.title) \(rec.content)".lowercased()
                if tokens.contains(where: { text.contains($0) }) {
                    matchedRecords.append(rec)
                    if matchedRecords.count >= topK { break }
                }
            }
        }

        return matchedRecords
    }

    /// Reflect: Synthesizes high-level observations and root-cause explanations across memory facts.
    public func reflect(query: String) async -> String {
        let recalled = await recall(query: query, topK: 4)
        guard !recalled.isEmpty else {
            return "🧠 Native Swift Cognitive Reflection: No conflicting memory constraints found for '\(query)'."
        }

        var synthesis = "🧠 Native Swift Cognitive Reflection across \(recalled.count) recalled record(s):\n"
        for rec in recalled {
            synthesis += "• [\(rec.type.rawValue.uppercased())] \(rec.title): \(rec.content.prefix(120))\n"
        }
        return synthesis
    }

    /// Total active records count.
    public var count: Int {
        records.count
    }
}

// VectorStore.swift
// AdventurersCore — Embedded Vector Storage & Cosine Similarity Index
// High-performance embedded indexing for local code semantic search and embeddings.

import Foundation

public struct CodeEmbeddingChunk: Sendable, Codable, Equatable {
    public let id: String
    public let filePath: String
    public let lineStart: Int
    public let lineEnd: Int
    public let symbol: String?
    public let text: String
    public let vector: [Float]

    public init(
        id: String = UUID().uuidString,
        filePath: String,
        lineStart: Int,
        lineEnd: Int,
        symbol: String? = nil,
        text: String,
        vector: [Float]
    ) {
        self.id = id
        self.filePath = filePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.symbol = symbol
        self.text = text
        self.vector = vector
    }
}

public struct VectorSearchResult: Sendable, Equatable {
    public let chunk: CodeEmbeddingChunk
    public let similarity: Float

    public init(chunk: CodeEmbeddingChunk, similarity: Float) {
        self.chunk = chunk
        self.similarity = similarity
    }
}

public actor VectorStore {
    private var chunks: [String: CodeEmbeddingChunk] = [:]

    public init() {}

    /// Inserts or updates an embedding chunk.
    public func insert(chunk: CodeEmbeddingChunk) {
        chunks[chunk.id] = chunk
    }

    /// Inserts a batch of embedding chunks.
    public func insertBatch(_ batch: [CodeEmbeddingChunk]) {
        for chunk in batch {
            chunks[chunk.id] = chunk
        }
    }

    /// Queries the vector store with cosine similarity ranking.
    public func search(queryVector: [Float], topK: Int = 5, minSimilarity: Float = 0.0) -> [VectorSearchResult] {
        var results: [VectorSearchResult] = []

        for chunk in chunks.values {
            let sim = cosineSimilarity(queryVector, chunk.vector)
            if sim >= minSimilarity {
                results.append(VectorSearchResult(chunk: chunk, similarity: sim))
            }
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(topK)
            .map { $0 }
    }

    /// Total number of indexed chunks.
    public var count: Int {
        chunks.count
    }

    /// Clears all vectors.
    public func clear() {
        chunks.removeAll()
    }

    // MARK: - SIMD / Accelerated Cosine Similarity

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        var dot: Float = 0.0
        var normA: Float = 0.0
        var normB: Float = 0.0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0.000001 else { return 0.0 }
        return dot / denom
    }
}

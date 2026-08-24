// AdventurersCore - Open Knowledge Format (OKF) & Skills Knowledge Packets
// Pure Swift system for modular, token-efficient knowledge distribution and deterministic skill execution.

import Foundation

// MARK: - OKF Knowledge Packet Model

public struct KnowledgePacket: Identifiable, Codable, Sendable {
    public let id: String
    public let schemaVersion: String
    public let title: String
    public let category: String
    public let summary: String
    public let tags: [String]
    public let content: String
    public let constraints: [String]
    public let codeSnippets: [String: String] // language -> code snippet
    public let verifiedAt: Date

    public init(
        id: String,
        schemaVersion: String = "okf/1.0",
        title: String,
        category: String,
        summary: String,
        tags: [String] = [],
        content: String,
        constraints: [String] = [],
        codeSnippets: [String: String] = [:],
        verifiedAt: Date = Date()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.title = title
        self.category = category
        self.summary = summary
        self.tags = tags
        self.content = content
        self.constraints = constraints
        self.codeSnippets = codeSnippets
        self.verifiedAt = verifiedAt
    }
}

// MARK: - Knowledge Packet Registry

public actor KnowledgeRegistry {
    public static let shared = KnowledgeRegistry()

    private var packets: [String: KnowledgePacket] = [:]
    private let fileManager = FileManager.default
    private let directoryOverride: URL?

    /// - Parameter directoryOverride: When non-nil, packets persist here instead of the real
    ///   `~/.adventurers/knowledge` directory. Intended for tests.
    public init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        var initial = Self.defaultKnowledgePackets()
        let dir = Self.resolveDirectory(override: directoryOverride)
        for (id, packet) in Self.loadPackets(from: dir) {
            initial[id] = packet
        }
        self.packets = initial
    }

    private static func resolveDirectory(override: URL?) -> URL {
        let base = override ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".adventurers", isDirectory: true)
            .appendingPathComponent("knowledge", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private static func loadPackets(from directory: URL) -> [String: KnowledgePacket] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [String: KnowledgePacket] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let packet = try? JSONDecoder().decode(KnowledgePacket.self, from: data) else {
                continue
            }
            result[packet.id] = packet
        }
        return result
    }

    private static func defaultKnowledgePackets() -> [String: KnowledgePacket] {
        var map: [String: KnowledgePacket] = [:]
        let p1 = KnowledgePacket(
            id: "swift6-concurrency",
            title: "Swift 6 Concurrency & Actor Isolation Rules",
            category: "Languages & Frameworks",
            summary: "Core rules for Swift 6 strict concurrency, @MainActor isolation, nonisolated helpers, and Sendable conformance.",
            tags: ["swift", "swift6", "concurrency", "actor", "mainactor", "sendable"],
            content: """
            1. Never call actor-isolated methods synchronously from synchronous nonisolated initializers.
            2. Mark AppKit/SwiftUI delegates and UI state mutations with @MainActor.
            3. Types crossing actor boundaries must conform to Sendable.
            4. Use Task.detached for background I/O, yielding back to @MainActor for UI state updates.
            """,
            constraints: [
                "Compile with .swiftLanguageMode(.v6)",
                "Zero data race warnings permitted"
            ],
            codeSnippets: [
                "swift": """
                @MainActor
                public final class ViewModel: ObservableObject {
                    @Published public var state: State = .idle
                }
                """
            ]
        )
        let p2 = KnowledgePacket(
            id: "diff-engine-safety",
            title: "Deterministic Diff Patching & Atomic Rollback",
            category: "Harness Safety",
            summary: "Best practices for multi-hunk patch application, context alignment, and atomic file restoration.",
            tags: ["diff", "patch", "git", "safety", "rollback"],
            content: """
            1. Always take an atomic snapshot checkpoint prior to applying multi-hunk patches.
            2. Match context lines with whitespace normalization.
            3. If context lines do not match surrounding buffer, reject patch immediately to prevent code corruption.
            """,
            constraints: [
                "Fail-closed on corrupt hunk header",
                "Mirror all changes to disk atomically"
            ]
        )
        map[p1.id] = p1
        map[p2.id] = p2
        return map
    }

    /// Base knowledge directory: ~/.adventurers/knowledge/ (or `directoryOverride` in tests).
    public var baseDirectory: URL {
        Self.resolveDirectory(override: directoryOverride)
    }

    /// Registers a packet in memory and persists it to disk so it survives relaunch. The two
    /// built-in default packets (registered in `init`, never round-tripped through this) are not
    /// affected by this — only packets registered after construction get written to disk.
    public func registerPacket(_ packet: KnowledgePacket) {
        packets[packet.id] = packet
        persist(packet)
    }

    /// Convenience matching the shape of the old Docker-based Hindsight `/api/v1/knowledge/ingest`
    /// endpoint this replaces — same fields, but native, persistent, and zero-dependency.
    @discardableResult
    public func ingest(
        title: String,
        content: String,
        category: String = "Notes",
        summary: String? = nil,
        tags: [String] = []
    ) -> KnowledgePacket {
        let packet = KnowledgePacket(
            id: UUID().uuidString,
            title: title,
            category: category,
            summary: summary ?? String(content.prefix(160)),
            tags: tags,
            content: content
        )
        registerPacket(packet)
        return packet
    }

    public func deletePacket(id: String) {
        packets.removeValue(forKey: id)
        let url = baseDirectory.appendingPathComponent("\(id).json")
        try? fileManager.removeItem(at: url)
    }

    public func getPacket(id: String) -> KnowledgePacket? {
        return packets[id]
    }

    public func allPackets() -> [KnowledgePacket] {
        return Array(packets.values).sorted { $0.title < $1.title }
    }

    private func persist(_ packet: KnowledgePacket) {
        let url = baseDirectory.appendingPathComponent("\(packet.id).json")
        guard let data = try? JSONEncoder().encode(packet) else { return }
        try? data.write(to: url)
    }

    /// Finds relevant knowledge packets for a given prompt or tool query.
    public func matchPackets(for query: String, limit: Int = 3) -> [KnowledgePacket] {
        let queryTokens = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
        guard !queryTokens.isEmpty else { return [] }

        var scored: [(packet: KnowledgePacket, score: Int)] = []

        for packet in packets.values {
            var score = 0
            let titleLower = packet.title.lowercased()
            let summaryLower = packet.summary.lowercased()
            let tagsLower = packet.tags.map { $0.lowercased() }

            for token in queryTokens {
                if titleLower.contains(token) { score += 5 }
                if summaryLower.contains(token) { score += 2 }
                if tagsLower.contains(where: { $0.contains(token) }) { score += 4 }
            }

            if score > 0 {
                scored.append((packet, score))
            }
        }

        return scored.sorted { $0.score > $1.score }.prefix(limit).map { $0.packet }
    }

    /// Performs a deduplication pass over all stored packets on disk.
    /// Groups by normalized title and category, keeping the most recent verified packet and removing duplicates.
    @discardableResult
    public func deduplicatePackets() -> Int {
        var seen: [String: KnowledgePacket] = [:]
        var removedCount = 0

        let sorted = packets.values.sorted { $0.verifiedAt > $1.verifiedAt }
        for packet in sorted {
            let key = "\(packet.category.lowercased().trimmingCharacters(in: .whitespaces))::\(packet.title.lowercased().trimmingCharacters(in: .whitespaces))"
            if let existing = seen[key] {
                // Duplicate found: delete the older one
                deletePacket(id: packet.id)
                removedCount += 1
            } else {
                seen[key] = packet
            }
        }
        return removedCount
    }
}

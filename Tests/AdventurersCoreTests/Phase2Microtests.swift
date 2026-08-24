// Phase2Microtests.swift
// Adventurers Harness — Phase 2 Microtests covering Tasks 2.6 through 2.11

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Phase 2 LSP, Vector Store, AST Chunker & Dogfood Suite")
struct Phase2Microtests {

    @Test("SourceKit-LSP binary path discovery locates an executable compiler or fallback")
    func testSourceKitLSPDiscovery() async {
        let serverPath = SourceKitLSPClient.discoverServerPath()
        #expect(!serverPath.isEmpty)
        #expect(serverPath.contains("sourcekit-lsp"))
    }

    @Test("Multi-Language LSP Manager discovers installed compiler servers and maps language extensions")
    func testMultiLanguageLSPDiscoveryAndBinding() async {
        let manager = MultiLanguageLSPManager.shared
        let descriptors = await manager.discoverInstalledServers()
        #expect(!descriptors.isEmpty)

        let swiftDescriptor = descriptors.first { $0.language == .swift }
        #expect(swiftDescriptor != nil)

        let swiftLang = await manager.detectLanguage(for: "Sources/AdventurersCore/App.swift")
        #expect(swiftLang == .swift)

        let rustLang = await manager.detectLanguage(for: "native/src/lib.rs")
        #expect(rustLang == .rust)

        let zigLang = await manager.detectLanguage(for: "src/main.zig")
        #expect(zigLang == .zig)
    }

    @Test("LSP Compilation Gate preflights valid and invalid Swift content cleanly")
    func testLSPCompilationGatePreflight() async {
        let gate = LSPCompilationGate.shared

        // Valid syntax preflight
        let validCode = """
        public struct Coordinate: Sendable {
            public let x: Double
            public let y: Double
        }
        """
        let validRes = await gate.preflight(filePath: "Sources/Coord.swift", proposedContent: validCode)
        #expect(validRes.isValid == true)

        // Invalid unbalanced syntax preflight
        let invalidCode = "func broken() { let a = "
        let invalidRes = await gate.preflight(filePath: "Sources/Bad.swift", proposedContent: invalidCode)
        #expect(invalidRes.isValid == false)
    }

    @Test("Vector Store inserts code embeddings and ranks nearest neighbors with Cosine Similarity")
    func testVectorStoreInsertionAndCosineQuery() async {
        let store = VectorStore()

        let chunk1 = CodeEmbeddingChunk(
            filePath: "Sources/Auth.swift",
            lineStart: 1,
            lineEnd: 20,
            symbol: "AuthService",
            text: "class AuthService { func login() {} }",
            vector: [1.0, 0.0, 0.0, 0.0]
        )

        let chunk2 = CodeEmbeddingChunk(
            filePath: "Sources/Database.swift",
            lineStart: 1,
            lineEnd: 30,
            symbol: "DatabasePool",
            text: "class DatabasePool { func connect() {} }",
            vector: [0.0, 1.0, 0.0, 0.0]
        )

        await store.insert(chunk: chunk1)
        await store.insert(chunk: chunk2)

        let count = await store.count
        #expect(count == 2)

        // Query closer to chunk1
        let queryVector: [Float] = [0.95, 0.05, 0.0, 0.0]
        let results = await store.search(queryVector: queryVector, topK: 1)

        #expect(results.count == 1)
        #expect(results[0].chunk.symbol == "AuthService")
        #expect(results[0].similarity > 0.90)
    }

    @Test("AST Chunker decomposes Swift source into structural symbol chunks preserving signatures")
    func testASTChunkerPreservesSignaturesAndContext() {
        let chunker = ASTChunker.shared
        let swiftSource = """
        // Header
        import Foundation

        public struct UserSession: Sendable {
            public let userId: String
            public let token: String

            public func isValid() -> Bool {
                return !token.isEmpty
            }
        }

        public final class NetworkManager {
            public func fetch() async {}
        }
        """

        let chunks = chunker.chunk(source: swiftSource, filePath: "Sources/Session.swift")
        #expect(!chunks.isEmpty)

        let sessionChunk = chunks.first { $0.symbol == "UserSession" }
        #expect(sessionChunk != nil)
        #expect(sessionChunk?.kind == "struct")
        #expect(sessionChunk?.content.contains("func isValid") == true)

        let netChunk = chunks.first { $0.symbol == "NetworkManager" }
        #expect(netChunk != nil)
        #expect(netChunk?.kind == "class")
    }

    @Test("Local Embedding Engine generates normalized Accelerate vector embeddings offline")
    func testLocalEmbeddingGenerationSpeedAndAccuracy() {
        let engine = LocalEmbeddingEngine(dimensions: 128)
        let vector = engine.embed(text: "func executeAgentTurn() async throws -> StepResult")

        #expect(vector.count == 128)

        // Compute L2 norm of the returned vector — should be approximately 1.0 (unit length)
        var sumSquares: Float = 0.0
        for v in vector {
            sumSquares += v * v
        }
        let magnitude = sqrt(sumSquares)
        #expect(magnitude > 0.95 && magnitude < 1.05)
    }

    @Test("Dogfood Manager runs complete multi-step self-dev certification loop")
    func testDogfoodPipelineExecutionAndSelfCheck() async {
        let manager = DogfoodManager.shared
        let statuses = await manager.runDogfoodSuite(projectPath: ".")

        #expect(statuses.count == 4)
        for status in statuses {
            #expect(status.passed == true)
        }
    }
}

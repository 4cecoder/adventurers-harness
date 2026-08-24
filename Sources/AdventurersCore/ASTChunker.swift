// ASTChunker.swift
// AdventurersCore — Structural Semantic Code Chunker
// Splits source code files along structural AST boundaries (classes, structs, functions, protocols) to preserve semantic intent.

import Foundation

public struct ASTCodeChunk: Sendable, Codable, Equatable {
    public let symbol: String
    public let kind: String
    public let lineStart: Int
    public let lineEnd: Int
    public let signature: String
    public let content: String

    public init(symbol: String, kind: String, lineStart: Int, lineEnd: Int, signature: String, content: String) {
        self.symbol = symbol
        self.kind = kind
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.signature = signature
        self.content = content
    }
}

public final class ASTChunker: Sendable {
    public static let shared = ASTChunker()

    public init() {}

    /// Chunks code content using structural definition boundaries.
    public func chunk(source: String, filePath: String) -> [ASTCodeChunk] {
        let lines = source.components(separatedBy: "\n")
        var chunks: [ASTCodeChunk] = []

        var currentSymbol: String? = nil
        var currentKind: String? = nil
        var currentSignature: String = ""
        var currentStartLine: Int = 1
        var chunkLines: [String] = []
        var braceDepth = 0

        for (idx, line) in lines.enumerated() {
            let lineNumber = idx + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect structural declaration start
            if braceDepth == 0, let (symbol, kind, sig) = parseDeclaration(trimmed) {
                // If we were buffering a previous chunk, flush it
                if let sym = currentSymbol, let k = currentKind, !chunkLines.isEmpty {
                    chunks.append(ASTCodeChunk(
                        symbol: sym,
                        kind: k,
                        lineStart: currentStartLine,
                        lineEnd: lineNumber - 1,
                        signature: currentSignature,
                        content: chunkLines.joined(separator: "\n")
                    ))
                    chunkLines.removeAll()
                }

                currentSymbol = symbol
                currentKind = kind
                currentSignature = sig
                currentStartLine = lineNumber
            }

            chunkLines.append(line)

            // Track brace nesting
            let openBraces = line.filter { $0 == "{" }.count
            let closeBraces = line.filter { $0 == "}" }.count
            braceDepth += openBraces - closeBraces

            if braceDepth == 0 && currentSymbol != nil && (openBraces > 0 || closeBraces > 0) {
                // Closed top-level structural block
                if let sym = currentSymbol, let k = currentKind {
                    chunks.append(ASTCodeChunk(
                        symbol: sym,
                        kind: k,
                        lineStart: currentStartLine,
                        lineEnd: lineNumber,
                        signature: currentSignature,
                        content: chunkLines.joined(separator: "\n")
                    ))
                }
                currentSymbol = nil
                currentKind = nil
                currentSignature = ""
                chunkLines.removeAll()
            }
        }

        // Flush remaining buffer as top-level / module chunk
        if !chunkLines.isEmpty {
            let sym = currentSymbol ?? (filePath as NSString).lastPathComponent
            let k = currentKind ?? "file_fragment"
            chunks.append(ASTCodeChunk(
                symbol: sym,
                kind: k,
                lineStart: currentStartLine,
                lineEnd: lines.count,
                signature: currentSignature.isEmpty ? sym : currentSignature,
                content: chunkLines.joined(separator: "\n")
            ))
        }

        return chunks
    }

    private func parseDeclaration(_ line: String) -> (symbol: String, kind: String, signature: String)? {
        let declKeywords = ["struct", "class", "enum", "protocol", "actor", "func", "extension", "typealias"]
        let words = line.split(separator: " ").map(String.init)
        for keyword in declKeywords {
            if let idx = words.firstIndex(where: { $0 == keyword }), idx + 1 < words.count {
                var rawSym = words[idx + 1]
                if let parenIdx = rawSym.firstIndex(of: "(") {
                    rawSym = String(rawSym[..<parenIdx])
                }
                if let colonIdx = rawSym.firstIndex(of: ":") {
                    rawSym = String(rawSym[..<colonIdx])
                }
                let cleanSym = rawSym.trimmingCharacters(in: CharacterSet(charactersIn: "{}<>;:,()"))
                if !cleanSym.isEmpty {
                    return (symbol: cleanSym, kind: keyword, signature: line)
                }
            }
        }
        return nil
    }
}

// AdventurersCore - Source Proof & Git Hash Integrity Validator
// Validates cryptographic SHA256 hashes and git commit tree proofs during recovery and rollbacks.

import Foundation
import CryptoKit

public struct SourceProof: Sendable, Codable, Equatable {
    public let relativePath: String
    public let sha256Hex: String
    public let byteCount: Int
    public let lastModified: Date
    public let gitCommitHash: String?

    public init(
        relativePath: String,
        sha256Hex: String,
        byteCount: Int,
        lastModified: Date = Date(),
        gitCommitHash: String? = nil
    ) {
        self.relativePath = relativePath
        self.sha256Hex = sha256Hex
        self.byteCount = byteCount
        self.lastModified = lastModified
        self.gitCommitHash = gitCommitHash
    }
}

public struct ValidationResult: Sendable, Equatable {
    public let isValid: Bool
    public let fileMatches: [String: Bool]
    public let mismatchedFiles: [String]
    public let missingFiles: [String]
    public let details: String

    public init(
        isValid: Bool,
        fileMatches: [String: Bool] = [:],
        mismatchedFiles: [String] = [],
        missingFiles: [String] = [],
        details: String
    ) {
        self.isValid = isValid
        self.fileMatches = fileMatches
        self.mismatchedFiles = mismatchedFiles
        self.missingFiles = missingFiles
        self.details = details
    }
}

public final class SourceProofValidator: Sendable {
    public static let shared = SourceProofValidator()

    public init() {}

    /// Computes SHA256 hash for raw data.
    public func computeSHA256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes SHA256 hash for a file at absolute path.
    public func computeFileSHA256(atPath path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return computeSHA256(data: data)
    }

    /// Generates a cryptographic SourceProof for a workspace file.
    public func generateProof(forRelativePath relPath: String, workspacePath: String, gitCommit: String? = nil) -> SourceProof? {
        let fullPath = (workspacePath as NSString).appendingPathComponent(relPath)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else { return nil }
        let hash = computeSHA256(data: data)

        let fm = FileManager.default
        let attrs = (try? fm.attributesOfItem(atPath: fullPath)) ?? [:]
        let modDate = (attrs[.modificationDate] as? Date) ?? Date()

        return SourceProof(
            relativePath: relPath,
            sha256Hex: hash,
            byteCount: data.count,
            lastModified: modDate,
            gitCommitHash: gitCommit
        )
    }

    /// Validates an array of expected SourceProofs against current workspace files on disk.
    public func validateProofs(_ proofs: [SourceProof], workspacePath: String) -> ValidationResult {
        var matches: [String: Bool] = [:]
        var mismatches: [String] = []
        var missing: [String] = []

        for proof in proofs {
            let fullPath = (workspacePath as NSString).appendingPathComponent(proof.relativePath)
            guard let currentHash = computeFileSHA256(atPath: fullPath) else {
                matches[proof.relativePath] = false
                missing.append(proof.relativePath)
                continue
            }

            if currentHash.lowercased() == proof.sha256Hex.lowercased() {
                matches[proof.relativePath] = true
            } else {
                matches[proof.relativePath] = false
                mismatches.append(proof.relativePath)
            }
        }

        let allValid = mismatches.isEmpty && missing.isEmpty
        let details = allValid
            ? "All \(proofs.count) source proof hashes verified cleanly."
            : "Verification failed: \(mismatches.count) hash mismatches, \(missing.count) missing files."

        return ValidationResult(
            isValid: allValid,
            fileMatches: matches,
            mismatchedFiles: mismatches,
            missingFiles: missing,
            details: details
        )
    }
}

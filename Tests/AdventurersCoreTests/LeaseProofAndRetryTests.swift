// AdventurersCoreTests - WorktreeLease, SourceProofValidator, and TransientRetryEngine Test Suite

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Worktree Lease, Source Proof & Transient Retry Suite")
struct LeaseProofAndRetryTests {

    @Test("Worktree Lease grants exclusive lock and rejects concurrent collision")
    func testWorktreeLeaseCollision() async {
        let manager = WorktreeLeaseManager.shared
        let path = "/tmp/test-workspace-\(UUID().uuidString)"
        let thread1 = UUID()
        let thread2 = UUID()

        let res1 = await manager.acquireLease(workspacePath: path, ownerThreadID: thread1, durationSeconds: 60, purpose: "Thread 1 agent turn")
        if case .acquired(let lease) = res1 {
            #expect(lease.ownerThreadID == thread1)
        } else {
            Issue.record("Expected thread 1 to acquire lease")
        }

        // Thread 2 tries to acquire same path -> should be denied
        let res2 = await manager.acquireLease(workspacePath: path, ownerThreadID: thread2, durationSeconds: 60, purpose: "Thread 2 agent turn")
        if case .denied(let existing, _) = res2 {
            #expect(existing.ownerThreadID == thread1)
        } else {
            Issue.record("Expected thread 2 to be denied")
        }

        let isLocked = await manager.isLockedByOther(workspacePath: path, currentThreadID: thread2)
        #expect(isLocked == true)

        // Release lease
        let released = await manager.releaseLease(workspacePath: path, ownerThreadID: thread1)
        #expect(released == true)

        // Now thread 2 can acquire
        let res3 = await manager.acquireLease(workspacePath: path, ownerThreadID: thread2, durationSeconds: 60, purpose: "Thread 2 agent turn")
        if case .acquired(let lease2) = res3 {
            #expect(lease2.ownerThreadID == thread2)
        } else {
            Issue.record("Expected thread 2 to acquire released lease")
        }

        _ = await manager.releaseLease(workspacePath: path, ownerThreadID: thread2)
    }

    @Test("Source Proof Validator calculates SHA256 and detects modified files")
    func testSourceProofValidation() throws {
        let validator = SourceProofValidator.shared
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let file1Rel = "main.swift"
        let file1Full = (tempDir as NSString).appendingPathComponent(file1Rel)
        let content1 = "print(\"Hello World\")\n"
        try content1.write(toFile: file1Full, atomically: true, encoding: .utf8)

        guard let proof = validator.generateProof(forRelativePath: file1Rel, workspacePath: tempDir, gitCommit: "abc1234") else {
            Issue.record("Failed to generate proof")
            return
        }

        #expect(proof.relativePath == file1Rel)
        #expect(proof.byteCount == content1.count)
        #expect(!proof.sha256Hex.isEmpty)

        // Validate clean match
        let validResult = validator.validateProofs([proof], workspacePath: tempDir)
        #expect(validResult.isValid == true)
        #expect(validResult.mismatchedFiles.isEmpty)

        // Mutate file -> validate mismatch
        let modified = "print(\"Modified Content\")\n"
        try modified.write(toFile: file1Full, atomically: true, encoding: .utf8)

        let mismatchResult = validator.validateProofs([proof], workspacePath: tempDir)
        #expect(mismatchResult.isValid == false)
        #expect(mismatchResult.mismatchedFiles.contains(file1Rel))

        try? FileManager.default.removeItem(atPath: tempDir)
    }

    @Test("Transient Retry Engine classifies transient vs permanent errors")
    func testTransientRetryClassification() {
        let engine = TransientRetryEngine.shared

        // 429 & 503 are transient
        let res429 = engine.classify(statusCode: 429, error: nil)
        #expect(res429 == .transient(suggestedDelay: 2.0))

        let res503 = engine.classify(statusCode: 503, error: nil)
        #expect(res503 == .transient(suggestedDelay: 1.0))

        // 401 & 400 are permanent
        let res401 = engine.classify(statusCode: 401, error: nil)
        if case .permanent = res401 {
            #expect(true)
        } else {
            Issue.record("Expected 401 to be permanent")
        }

        let res400 = engine.classify(statusCode: 400, error: nil)
        if case .permanent = res400 {
            #expect(true)
        } else {
            Issue.record("Expected 400 to be permanent")
        }
    }
}

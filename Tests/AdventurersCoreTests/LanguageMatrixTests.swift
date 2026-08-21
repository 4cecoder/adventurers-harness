// LanguageMatrixTests.swift
// AdventurersCoreTests — Unit Tests for Polyglot Language Matrix

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Polyglot Language Matrix Suite")
struct LanguageMatrixTests {

    @Test("LanguageMatrix returns appropriate guidance across all domains")
    func matrixCoverage() {
        for domain in WorkloadDomain.allCases {
            let guidance = LanguageMatrix.guidance(for: domain)
            #expect(!guidance.rationale.isEmpty)
            #expect(!guidance.strengths.isEmpty)
            #expect(!guidance.cliVerificationMethod.isEmpty)
        }
    }

    @Test("Low latency compute recommends C / Zig")
    func lowLatencyTarget() {
        let guidance = LanguageMatrix.guidance(for: .lowLatencyCompute)
        #expect(guidance.language == .cOrZig)
    }

    @Test("macOS native system recommends Swift 6")
    func macosTarget() {
        let guidance = LanguageMatrix.guidance(for: .macosNativeSystem)
        #expect(guidance.language == .swift)
    }
}

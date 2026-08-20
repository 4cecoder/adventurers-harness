// DuplicateInstallCleanerTests.swift
// AdventurersCoreTests — Unit Tests for Duplicate Install Detection & Cleanup

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Duplicate Install Cleaner Suite")
struct DuplicateInstallCleanerTests {

    /// Builds a minimal fake `.app` bundle on disk with just enough of an Info.plist for
    /// `Bundle(path:)` to read `CFBundleIdentifier`/`CFBundleShortVersionString`.
    private func makeFakeApp(
        in directory: URL,
        name: String,
        bundleIdentifier: String,
        version: String,
        build: String = "1"
    ) throws -> String {
        let appURL = directory.appendingPathComponent("\(name).app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))

        return (appURL.path as NSString).standardizingPath
    }

    @Test("Finds only bundles matching the expected identifier, tagging the running instance")
    func findsMatchingCopiesAndTagsRunningInstance() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adventurers-dup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let runningPath = try makeFakeApp(in: tempDir, name: "Adventurers-Current", bundleIdentifier: DuplicateInstallCleaner.expectedBundleIdentifier, version: "2.4.0")
        let oldPath = try makeFakeApp(in: tempDir, name: "Adventurers-Old", bundleIdentifier: DuplicateInstallCleaner.expectedBundleIdentifier, version: "2.1.0")
        _ = try makeFakeApp(in: tempDir, name: "SomeOtherApp", bundleIdentifier: "com.example.unrelated", version: "1.0.0")

        let copies = DuplicateInstallCleaner.findInstalledCopies(runningBundlePath: runningPath, applicationsDirectory: tempDir.path)

        #expect(copies.count == 2)
        #expect(copies.contains { $0.bundlePath == runningPath && $0.isRunningInstance })
        #expect(copies.contains { $0.bundlePath == oldPath && !$0.isRunningInstance })
    }

    @Test("removableCopies excludes the running instance and unrelated bundle identifiers")
    func removableCopiesExcludesRunningInstance() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adventurers-dup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let runningPath = try makeFakeApp(in: tempDir, name: "Adventurers", bundleIdentifier: DuplicateInstallCleaner.expectedBundleIdentifier, version: "2.4.0")
        _ = try makeFakeApp(in: tempDir, name: "Adventurers 2", bundleIdentifier: DuplicateInstallCleaner.expectedBundleIdentifier, version: "2.0.0")

        let removable = DuplicateInstallCleaner.removableCopies(runningBundlePath: runningPath, applicationsDirectory: tempDir.path)

        #expect(removable.count == 1)
        #expect(removable.allSatisfy { !$0.isRunningInstance })
    }

    @Test("moveToTrash refuses to remove anything outside /Applications")
    func moveToTrashRefusesOutsideApplications() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adventurers-dup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let strayPath = try makeFakeApp(in: tempDir, name: "Adventurers-Stray", bundleIdentifier: DuplicateInstallCleaner.expectedBundleIdentifier, version: "1.0.0")
        let copy = InstalledAppCopy(bundlePath: strayPath, bundleIdentifier: DuplicateInstallCleaner.expectedBundleIdentifier, version: "1.0.0", build: "1", isRunningInstance: false)

        #expect(throws: DuplicateInstallCleanerError.self) {
            try DuplicateInstallCleaner.moveToTrash(copy, runningBundlePath: "/Applications/Adventurers.app", applicationsDirectory: "/Applications")
        }

        // The stray bundle must still exist — the refusal must happen before any filesystem mutation.
        #expect(FileManager.default.fileExists(atPath: strayPath))
    }

    @Test("moveToTrash refuses to remove the currently running instance")
    func moveToTrashRefusesRunningInstance() throws {
        let tempDir = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let copy = InstalledAppCopy(bundlePath: "/Applications/Adventurers.app", bundleIdentifier: DuplicateInstallCleaner.expectedBundleIdentifier, version: "2.4.0", build: "1", isRunningInstance: true)

        #expect(throws: DuplicateInstallCleanerError.self) {
            try DuplicateInstallCleaner.moveToTrash(copy, runningBundlePath: "/Applications/Adventurers.app", applicationsDirectory: tempDir.path)
        }
    }
}

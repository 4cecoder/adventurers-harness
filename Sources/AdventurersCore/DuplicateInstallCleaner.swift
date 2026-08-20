// AdventurersCore - DuplicateInstallCleaner
// Finds and safely removes stray copies of this app left behind by manual drag-installs or
// earlier updates, so an "update" doesn't quietly leave old versions scattered around.
//
// Scope is deliberately narrow: /Applications only. This never inspects or touches ~/Downloads,
// ~/Desktop, or any other user folder — a stray zip/dmg the user is keeping on purpose in one of
// those locations is not this feature's business, and auto-deleting inside general-purpose user
// folders is exactly the kind of "deleted something I didn't mean to lose" risk worth avoiding.

import Foundation

public struct InstalledAppCopy: Identifiable, Sendable, Equatable {
    public let id: String
    public let bundlePath: String
    public let bundleIdentifier: String
    public let version: String
    public let build: String
    public let isRunningInstance: Bool

    public init(bundlePath: String, bundleIdentifier: String, version: String, build: String, isRunningInstance: Bool) {
        self.id = bundlePath
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.isRunningInstance = isRunningInstance
    }
}

public enum DuplicateInstallCleanerError: Error, LocalizedError, Sendable {
    case outsideApplications(String)
    case isRunningInstance

    public var errorDescription: String? {
        switch self {
        case .outsideApplications(let path):
            return "Refusing to remove '\(path)' — it is outside /Applications."
        case .isRunningInstance:
            return "Refusing to remove the copy that is currently running."
        }
    }
}

public enum DuplicateInstallCleaner {
    public static let expectedBundleIdentifier = "com.bytecats.adventurers"

    /// Scans the top level of `applicationsDirectory` (never anywhere else) for `.app` bundles
    /// sharing this app's bundle identifier, including the one currently running.
    public static func findInstalledCopies(
        runningBundlePath: String = Bundle.main.bundlePath,
        applicationsDirectory: String = "/Applications"
    ) -> [InstalledAppCopy] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: applicationsDirectory) else {
            return []
        }

        let standardizedRunningPath = (runningBundlePath as NSString).standardizingPath
        var results: [InstalledAppCopy] = []

        for entry in entries where entry.hasSuffix(".app") {
            let bundlePath = (applicationsDirectory as NSString).appendingPathComponent(entry)
            guard let bundle = Bundle(path: bundlePath),
                  let identifier = bundle.bundleIdentifier,
                  identifier == expectedBundleIdentifier else { continue }

            let standardizedBundlePath = (bundlePath as NSString).standardizingPath
            let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
            let build = (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "0"

            results.append(InstalledAppCopy(
                bundlePath: standardizedBundlePath,
                bundleIdentifier: identifier,
                version: version,
                build: build,
                isRunningInstance: standardizedBundlePath == standardizedRunningPath
            ))
        }

        return results
    }

    /// Copies that are safe to offer for removal: matching bundle identifier, found strictly
    /// inside `applicationsDirectory`, and not the copy currently running.
    public static func removableCopies(
        runningBundlePath: String = Bundle.main.bundlePath,
        applicationsDirectory: String = "/Applications"
    ) -> [InstalledAppCopy] {
        findInstalledCopies(runningBundlePath: runningBundlePath, applicationsDirectory: applicationsDirectory)
            .filter { !$0.isRunningInstance }
    }

    /// Moves a duplicate copy to the Trash — never a permanent delete, so a mistaken removal is
    /// still recoverable. Independently re-checks the /Applications-only and
    /// not-the-running-instance constraints rather than trusting the caller's filtering.
    @discardableResult
    public static func moveToTrash(
        _ copy: InstalledAppCopy,
        runningBundlePath: String = Bundle.main.bundlePath,
        applicationsDirectory: String = "/Applications"
    ) throws -> Bool {
        let standardizedAppsDir = (applicationsDirectory as NSString).standardizingPath
        guard copy.bundlePath.hasPrefix(standardizedAppsDir + "/") else {
            throw DuplicateInstallCleanerError.outsideApplications(copy.bundlePath)
        }
        let standardizedRunningPath = (runningBundlePath as NSString).standardizingPath
        guard copy.bundlePath != standardizedRunningPath else {
            throw DuplicateInstallCleanerError.isRunningInstance
        }

        try FileManager.default.trashItem(at: URL(fileURLWithPath: copy.bundlePath), resultingItemURL: nil)
        return true
    }
}

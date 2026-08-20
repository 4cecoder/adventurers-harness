//
//  AppUpdateManager.swift
//  Adventurers Harness
//
//  Thin, app-branded facade over Sparkle (https://sparkle-project.org), which does the actual
//  security-sensitive work: signature-verified download, atomic in-place replacement of the
//  running .app bundle, and relaunch. Sparkle owns the download/verify/install/relaunch pipeline
//  and its own native consent UI (SPUStandardUserDriver); this class only mirrors state via
//  SPUUpdaterDelegate so the app's existing status-bar badge and Settings pane can show
//  "update available" without re-implementing any of the update mechanics by hand.
//
//  Feed URL and the EdDSA public key used to verify update signatures are configured in
//  Info.plist (SUFeedURL / SUPublicEDKey) by scripts/package_app.sh — see docs/updating.md for
//  how the signing key is generated and where the private half is stored.
//

import SwiftUI
import AppKit
import Sparkle

// MARK: - Update Status (mirrors Sparkle's delegate callbacks for display purposes only)

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(version: String)
    case failed(error: String)
}

// MARK: - App Update Manager

@Observable
@MainActor
public final class AppUpdateManager: NSObject, SPUUpdaterDelegate {
    public static let shared = AppUpdateManager()

    public let currentVersion: String = "2.4.0"
    public let currentBuild: String = "2026.08.19"
    public let repoOwner: String = "4cecoder"
    public let repoName: String = "adventurers-harness"

    public var status: UpdateStatus = .idle
    public private(set) var canCheckForUpdates: Bool = false

    // `SPUUpdaterDelegate` can only be supplied at construction (there's no settable property on
    // `SPUUpdater` afterward), but building the controller needs `self` as that delegate — which
    // isn't valid to hand out until after `super.init()` completes. Hence the implicitly-unwrapped
    // optional: it's nil only for the instant between `super.init()` and the assignment below.
    private var controller: SPUStandardUpdaterController!
    private var canCheckObservation: NSKeyValueObservation?

    public var isUpdateAvailable: Bool {
        if case .updateAvailable = status { return true }
        return false
    }

    public var releasesURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            guard let self, let newValue = change.newValue else { return }
            Task { @MainActor in self.canCheckForUpdates = newValue }
        }
    }

    /// Whether Sparkle checks for updates automatically in the background (bound to the
    /// "Check for updates on launch" setting).
    public var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Triggers a user-initiated check. Sparkle shows its own native alert for everything from
    /// here on — found update, release notes, download progress, and install/relaunch consent —
    /// so there is nothing else for this method to drive.
    public func checkForUpdates() {
        status = .checking
        controller.updater.checkForUpdates()
    }

    /// Silent background check (no alert if already up to date), used on launch.
    public func checkForUpdatesInBackground() {
        controller.updater.checkForUpdatesInBackground()
    }

    public func openReleasePage() {
        NSWorkspace.shared.open(releasesURL)
    }

    // MARK: - SPUUpdaterDelegate

    public nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        nil // Use the SUFeedURL configured in Info.plist.
    }

    public nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.status = .updateAvailable(version: item.displayVersionString)
        }
    }

    public nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.status = .upToDate(checkedAt: Date())
        }
    }

    public nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            self.status = .failed(error: error.localizedDescription)
        }
    }
}

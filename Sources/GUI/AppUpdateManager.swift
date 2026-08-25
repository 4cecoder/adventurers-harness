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
import os.lock

// MARK: - Update Channel

/// Release train the user opts into. Maps to `<sparkle:channel>` tags in appcast.xml: CI tags
/// alpha builds (every push to master) and beta builds (`vX.Y.Z-beta.N` tags) with those channel
/// names; plain `vX.Y.Z` stable tags carry no channel tag. Sparkle always includes the default
/// (stable) channel regardless of `allowedChannels`, so each tier is additive — picking Alpha
/// means "stable + beta + alpha", not "alpha only".
public enum UpdateChannel: String, CaseIterable, Codable, Sendable {
    case stable
    case beta
    case alpha

    public var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .beta: return "Beta"
        case .alpha: return "Alpha"
        }
    }

    public var explanation: String {
        switch self {
        case .stable: return "Tagged releases only. Recommended for most people."
        case .beta: return "Stable releases plus beta pre-releases."
        case .alpha: return "Every build — stable, beta, and the latest master build. Most likely to break."
        }
    }

    /// Additional channels Sparkle should also look for updates in, beyond the always-included
    /// default/stable channel.
    var allowedChannels: Set<String> {
        switch self {
        case .stable: return []
        case .beta: return ["beta"]
        case .alpha: return ["alpha", "beta"]
        }
    }
}

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

    public var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }
    public var currentBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? currentVersion
    }
    public let repoOwner: String = "4cecoder"
    public let repoName: String = "adventurers-harness"

    public var status: UpdateStatus = .idle
    public private(set) var canCheckForUpdates: Bool = false

    /// Which release train to look for updates in. Persisted by `SettingsModel`; assign this
    /// (rather than mutating it via Sparkle directly) whenever the user changes it in Settings.
    ///
    /// Backed by a lock instead of a plain `@Observable` stored property because Sparkle's
    /// `allowedChannels(for:)` delegate callback must return synchronously and isn't guaranteed
    /// to run on the main actor — there's no `await`-based hop available here the way the other
    /// (async) delegate methods below use.
    public nonisolated var updateChannel: UpdateChannel {
        get { updateChannelStorage.withLock { $0 } }
        set { updateChannelStorage.withLock { $0 = newValue } }
    }
    private let updateChannelStorage = OSAllocatedUnfairLock<UpdateChannel>(initialState: .stable)

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

    /// Whether the packaged app ships a Sparkle EdDSA verification key. Ad-hoc/local builds
    /// (packaged with SPARKLE_PUBLIC_KEY unset) have an empty SUPublicEDKey — automatic
    /// background checks are suppressed in that case since Sparkle cannot verify signatures.
    private var hasUpdateSigningKey: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !key.isEmpty
    }

    /// Whether Sparkle checks for updates automatically in the background (bound to the
    /// "Check for updates on launch" setting).
    public var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = hasUpdateSigningKey ? newValue : false }
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
        guard hasUpdateSigningKey else { return }
        controller.updater.checkForUpdatesInBackground()
    }

    public func openReleasePage() {
        NSWorkspace.shared.open(releasesURL)
    }

    // MARK: - SPUUpdaterDelegate

    public nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        nil // Use the SUFeedURL configured in Info.plist.
    }

    public nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        updateChannel.allowedChannels
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

//
//  AppUpdateManager.swift
//  Adventurers Harness
//
//  Automated update checking, semantic version comparison, and direct release
//  downloading based on the public GitHub repository (4cecoder/adventurers-harness).
//

import SwiftUI
import AppKit

// MARK: - GitHub Release Data Models

public struct GitHubRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    public var versionString: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    public var dmgAsset: GitHubAsset? {
        assets.first { $0.name.hasSuffix(".dmg") }
    }

    public var zipAsset: GitHubAsset? {
        assets.first { $0.name.hasSuffix(".zip") }
    }
}

public struct GitHubAsset: Codable, Sendable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int
    public let contentType: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
        case contentType = "content_type"
    }

    public var formattedSize: String {
        let mb = Double(size) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Update Status

public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(release: GitHubRelease)
    case downloading(progress: Double)
    case readyToInstall(dmgURL: URL)
    case failed(error: String)

    public static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking):
            return true
        case (.upToDate(let a), .upToDate(let b)):
            return a == b
        case (.updateAvailable(let a), .updateAvailable(let b)):
            return a.tagName == b.tagName
        case (.downloading(let a), .downloading(let b)):
            return a == b
        case (.readyToInstall(let a), .readyToInstall(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - App Update Manager

@Observable
@MainActor
public final class AppUpdateManager: NSObject, URLSessionDownloadDelegate {
    public static let shared = AppUpdateManager()

    public let currentVersion: String = "2.4.0"
    public let currentBuild: String = "2026.08.19"
    public let repoOwner: String = "4cecoder"
    public let repoName: String = "adventurers-harness"

    public var status: UpdateStatus = .idle
    public var latestRelease: GitHubRelease? = nil
    public var lastCheckedDate: Date? = nil
    public var showsUpdateModal: Bool = false
    public var downloadProgress: Double = 0.0

    private var downloadTask: URLSessionDownloadTask?
    private var activeDownloadURL: URL?

    public var isUpdateAvailable: Bool {
        switch status {
        case .updateAvailable, .readyToInstall:
            return true
        default:
            return false
        }
    }

    public var isBusy: Bool {
        switch status {
        case .checking, .downloading:
            return true
        default:
            return false
        }
    }

    public var releasesURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    }

    private override init() {
        super.init()
    }

    // MARK: - Check for Updates

    public func checkForUpdates(silent: Bool = false) {
        guard status != .checking else { return }
        status = .checking

        Task {
            let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("AdventurersHarness/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10.0

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "AppUpdateManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid network response."])
                }

                if httpResponse.statusCode == 404 {
                    // No releases published yet on repo
                    self.status = .upToDate(checkedAt: Date())
                    self.lastCheckedDate = Date()
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw NSError(domain: "AppUpdateManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API HTTP \(httpResponse.statusCode)"])
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                self.latestRelease = release
                self.lastCheckedDate = Date()

                if isNewerVersion(remote: release.versionString, local: currentVersion) {
                    self.status = .updateAvailable(release: release)
                    if !silent {
                        self.showsUpdateModal = true
                    }
                } else {
                    self.status = .upToDate(checkedAt: Date())
                }
            } catch {
                if !silent {
                    self.status = .failed(error: error.localizedDescription)
                } else {
                    self.status = .idle
                }
            }
        }
    }

    // MARK: - Version Comparison

    public func isNewerVersion(remote: String, local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let localComponents = local.split(separator: ".").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        let count = max(remoteComponents.count, localComponents.count)
        for i in 0..<count {
            let r = i < remoteComponents.count ? remoteComponents[i] : 0
            let l = i < localComponents.count ? localComponents[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    // MARK: - Direct Download

    public func downloadAndInstall() {
        guard let release = latestRelease else {
            NSWorkspace.shared.open(releasesURL)
            return
        }

        guard let asset = release.dmgAsset ?? release.zipAsset,
              let assetURL = URL(string: asset.browserDownloadUrl) else {
            NSWorkspace.shared.open(URL(string: release.htmlUrl) ?? releasesURL)
            return
        }

        status = .downloading(progress: 0.0)
        downloadProgress = 0.0

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        let task = session.downloadTask(with: assetURL)
        self.downloadTask = task
        task.resume()
    }

    public func openReleasePage() {
        if let urlStr = latestRelease?.htmlUrl, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(releasesURL)
        }
    }

    public func openDownloadedFile(url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - URLSessionDownloadDelegate

    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in
                self.downloadProgress = progress
                self.status = .downloading(progress: progress)
            }
        }
    }

    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let fileName = "Adventurers-macOS-arm64.dmg"
        let destinationURL = downloadsDirectory.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destinationURL)
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            Task { @MainActor in
                self.activeDownloadURL = destinationURL
                self.status = .readyToInstall(dmgURL: destinationURL)
            }
        } catch {
            Task { @MainActor in
                self.status = .failed(error: "Could not save update to Downloads: \(error.localizedDescription)")
            }
        }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.status = .failed(error: error.localizedDescription)
            }
        }
    }
}

// MARK: - Update Modal View

public struct UpdateModalView: View {
    @Bindable var updateManager = AppUpdateManager.shared
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.adOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Software Update Available")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.adTextPrimary)

                    if let release = updateManager.latestRelease {
                        Text("Version \(release.versionString) is ready to install (Current: v\(updateManager.currentVersion))")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.adTextSecondary)
                    } else {
                        Text("A new release is available on GitHub")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.adTextSecondary)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color.adNavy)

            Divider().overlay(Color.adDivider)

            // Release Notes Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let release = updateManager.latestRelease {
                        if let name = release.name, !name.isEmpty {
                            Text(name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.adTextPrimary)
                        }

                        if let body = release.body, !body.isEmpty {
                            Text(body)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.adTextSecondary)
                                .lineSpacing(3)
                        } else {
                            Text("No release notes provided for this version.")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.adTextTertiary)
                        }

                        if let asset = release.dmgAsset {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.zipper")
                                Text("Installer: \(asset.name) (\(asset.formattedSize))")
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.adInfo)
                            .padding(.top, 6)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .background(Color.adBackground)

            Divider().overlay(Color.adDivider)

            // Bottom Actions & Progress
            VStack(spacing: 10) {
                if case .downloading(let progress) = updateManager.status {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Downloading update installer...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.adTextSecondary)
                            Spacer()
                            Text(String(format: "%.0f%%", progress * 100))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.adOrange)
                        }
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Color.adOrange)
                    }
                    .padding(.horizontal, 18)
                }

                HStack(spacing: 10) {
                    Button("View on GitHub") {
                        updateManager.openReleasePage()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adOrange)

                    Spacer()

                    Button("Later") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.adElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    if case .readyToInstall(let dmgURL) = updateManager.status {
                        Button {
                            updateManager.openDownloadedFile(url: dmgURL)
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.doc.fill")
                                Text("Open Installer DMG")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.adSuccess)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            updateManager.downloadAndInstall()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download & Install")
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.adOrange)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(updateManager.isBusy)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(Color.adCard)
        }
        .frame(width: 520, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.adDivider, lineWidth: 1))
    }
}

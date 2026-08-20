// CyberdeckPlayer.swift
// Adventurers Harness — Native Cyberpunk Audio & YouTube Vibe Station
// High-performance AVFoundation streaming engine with yt-dlp audio stream extraction.

import SwiftUI
import AVFoundation
import Combine

// MARK: - Preset Cyberpunk Radio Stations

public struct CyberStation: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let tag: String
    public let youtubeUrl: String
    public let iconName: String
    public let accentColorHex: UInt32

    public init(
        id: String,
        name: String,
        tag: String,
        youtubeUrl: String,
        iconName: String = "waveform",
        accentColorHex: UInt32 = 0x64D2FF
    ) {
        self.id = id
        self.name = name
        self.tag = tag
        self.youtubeUrl = youtubeUrl
        self.iconName = iconName
        self.accentColorHex = accentColorHex
    }

    public static let presets: [CyberStation] = [
        CyberStation(
            id: "synthwave-24-7",
            name: "Synthwave / Cyberpunk 24/7",
            tag: "RETROWAVE",
            youtubeUrl: "https://www.youtube.com/watch?v=4xDzrJKXOOY",
            iconName: "bolt.fill",
            accentColorHex: 0xBF5AF2
        ),
        CyberStation(
            id: "lofi-coding-chill",
            name: "Lofi Cyber Coding Beats",
            tag: "CHILL / FOCUS",
            youtubeUrl: "https://www.youtube.com/watch?v=jfKfPfyJRdk",
            iconName: "headphones",
            accentColorHex: 0x30D158
        ),
        CyberStation(
            id: "darksynth-action",
            name: "Darksynth & Industrial Cyber",
            tag: "HARDCORE",
            youtubeUrl: "https://www.youtube.com/watch?v=r_sP_S_S7hE",
            iconName: "flame.fill",
            accentColorHex: 0xFF453A
        ),
        CyberStation(
            id: "nightcity-ambient",
            name: "Night City Rain & Ambient",
            tag: "ATMOSPHERE",
            youtubeUrl: "https://www.youtube.com/watch?v=s5AwbQuqT08",
            iconName: "cloud.rain.fill",
            accentColorHex: 0x64D2FF
        )
    ]
}

// MARK: - Playback State Enum

public enum CyberPlaybackState: String, Sendable {
    case stopped = "Idle"
    case resolving = "Extracting Stream..."
    case buffering = "Buffering Audio..."
    case playing = "Streaming"
    case paused = "Paused"
    case error = "Stream Error"

    public var icon: String {
        switch self {
        case .stopped: return "headphones"
        case .resolving: return "antenna.radiowaves.left.and.right"
        case .buffering: return "arrow.triangle.2.circlepath"
        case .playing: return "waveform"
        case .paused: return "pause.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Audio Player Model

@MainActor
@Observable
public final class CyberdeckPlayerModel {
    public static let shared = CyberdeckPlayerModel()

    public var state: CyberPlaybackState = .stopped
    public var currentTitle: String = "Cyberdeck Radio (Off)"
    public var currentStation: CyberStation?
    public var customUrlInput: String = ""
    public var volume: Float = 0.6 {
        didSet {
            player?.volume = isMuted ? 0.0 : volume
        }
    }
    public var isMuted: Bool = false {
        didSet {
            player?.volume = isMuted ? 0.0 : volume
        }
    }
    public var errorMessage: String?
    public var isPopoverOpen: Bool = false

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?

    public init() {
        // Disabled by default on startup
    }

    /// Resolves YouTube URL via yt-dlp and streams audio natively using AVPlayer.
    public func playYouTube(url: String, title: String? = nil, station: CyberStation? = nil) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        state = .resolving
        currentTitle = title ?? "Resolving YouTube stream..."
        currentStation = station
        errorMessage = nil

        // Clean up previous playback
        stopPlayer()

        Task {
            do {
                let streamUrlString = try await Self.extractDirectAudioStreamUrl(youtubeUrl: trimmed)
                guard let streamURL = URL(string: streamUrlString) else {
                    throw NSError(domain: "CyberdeckPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid stream URL received from yt-dlp."])
                }

                // If no title provided, fetch video title
                var resolvedTitle = title
                if resolvedTitle == nil {
                    resolvedTitle = try? await Self.fetchVideoTitle(youtubeUrl: trimmed)
                }
                let finalTitle = resolvedTitle ?? "Cyberpunk Live Stream"

                await MainActor.run {
                    self.currentTitle = finalTitle
                    self.state = .buffering
                    self.startAVPlayer(with: streamURL)
                }
            } catch {
                await MainActor.run {
                    self.state = .error
                    self.errorMessage = error.localizedDescription
                    self.currentTitle = "Stream unavailable"
                }
            }
        }
    }

    /// Starts native AVPlayer with the resolved audio stream URL.
    private func startAVPlayer(with url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.volume = isMuted ? 0.0 : volume
        self.player = avPlayer

        // Observe player item status
        statusObservation = playerItem.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.state = .playing
                    self.player?.play()
                case .failed:
                    self.state = .error
                    self.errorMessage = item.error?.localizedDescription ?? "Playback failed"
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        avPlayer.play()
    }

    public func togglePlayPause() {
        guard let player = player else {
            if let st = currentStation {
                playStation(st)
            } else if !CyberStation.presets.isEmpty {
                playStation(CyberStation.presets[0])
            }
            return
        }

        if state == .playing {
            player.pause()
            state = .paused
        } else if state == .paused {
            player.play()
            state = .playing
        }
    }

    public func playStation(_ station: CyberStation) {
        playYouTube(url: station.youtubeUrl, title: station.name, station: station)
    }

    public func stop() {
        stopPlayer()
        state = .stopped
        currentTitle = "Cyberdeck Radio (Off)"
        currentStation = nil
        errorMessage = nil
    }

    private func stopPlayer() {
        statusObservation?.invalidate()
        statusObservation = nil
        player?.pause()
        player = nil
    }

    // MARK: - yt-dlp Audio Stream Extraction

    /// Invokes yt-dlp to extract the direct HTTPS audio streaming URL.
    nonisolated private static func extractDirectAudioStreamUrl(youtubeUrl: String) async throws -> String {
        let ytdlpPath = findYtDlpBinary()
        guard let binary = ytdlpPath else {
            throw NSError(
                domain: "CyberdeckPlayer",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "yt-dlp binary not found. Install via 'brew install yt-dlp' to stream YouTube audio."]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            // -g prints URL, -f bestaudio selects highest quality audio stream, --no-warnings suppresses noise
            process.arguments = ["-g", "-f", "bestaudio/best", "--no-warnings", youtubeUrl]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus == 0,
                   let output = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let firstLine = output.components(separatedBy: .newlines).first,
                   firstLine.hasPrefix("http") {
                    continuation.resume(returning: firstLine)
                } else {
                    let errStr = String(data: stderrData, encoding: .utf8) ?? "Failed to extract stream"
                    continuation.resume(throwing: NSError(
                        domain: "CyberdeckPlayer",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: errStr.components(separatedBy: .newlines).first ?? "yt-dlp failed"]
                    ))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Fetches the video title via yt-dlp.
    nonisolated private static func fetchVideoTitle(youtubeUrl: String) async throws -> String {
        guard let binary = findYtDlpBinary() else { return "YouTube Audio" }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["--get-title", "--no-warnings", youtubeUrl]

            let stdoutPipe = Pipe()
            process.standardOutput = stdoutPipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if let title = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    continuation.resume(returning: title)
                } else {
                    continuation.resume(returning: "YouTube Audio Stream")
                }
            } catch {
                continuation.resume(returning: "YouTube Audio Stream")
            }
        }
    }

    /// Locates the yt-dlp binary in standard macOS paths.
    nonisolated private static func findYtDlpBinary() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
            (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(".local/bin/yt-dlp")
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

// MARK: - Cyberdeck Radio Toolbar Pill

public struct CyberdeckRadioPill: View {
    @Bindable var model: CyberdeckPlayerModel = CyberdeckPlayerModel.shared
    @State private var wavePhase: Double = 0

    public init() {}

    private var isLive: Bool {
        model.state == .playing || model.state == .buffering || model.state == .resolving
    }

    private var pillBackground: Color {
        isLive ? Color.adNavy.opacity(0.8) : Color.adElevated
    }

    private var pillBorderColor: Color {
        isLive ? Color.cyan.opacity(0.4) : Color.adDivider
    }

    private var statusTitle: String {
        model.state == .stopped ? "Vibe Radio" : model.currentTitle
    }

    private var statusIconColor: Color {
        if model.state == .error {
            return Color.adError
        }
        return isLive ? Color.cyan : Color.adTextSecondary
    }

    private func barHeight(index: Int) -> CGFloat {
        let wave = sin(wavePhase + Double(index) * 1.2) + 1.0
        return CGFloat(4.0 + wave * 4.0)
    }

    public var body: some View {
        Button {
            model.isPopoverOpen.toggle()
        } label: {
            pillContent
        }
        .buttonStyle(.plain)
        .popover(isPresented: $model.isPopoverOpen, arrowEdge: .bottom) {
            CyberdeckPlayerPopoverView(model: model)
        }
        .help("Cyberdeck Vibe Radio & YouTube Audio Player")
    }

    @ViewBuilder
    private var pillContent: some View {
        HStack(spacing: 6) {
            leadingIndicator
            titleText
            trailingDot
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(pillBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(pillBorderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        if model.state == .playing {
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 2, height: barHeight(index: i))
                }
            }
            .frame(width: 14, height: 12)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                    wavePhase = .pi * 2
                }
            }
        } else {
            Image(systemName: model.state.icon)
                .font(.system(size: 11))
                .foregroundStyle(statusIconColor)
        }
    }

    @ViewBuilder
    private var titleText: some View {
        Text(statusTitle)
            .font(.system(size: 11, weight: isLive ? .semibold : .regular))
            .foregroundStyle(isLive ? Color.adTextPrimary : Color.adTextSecondary)
            .lineLimit(1)
            .frame(maxWidth: 160, alignment: .leading)
    }

    @ViewBuilder
    private var trailingDot: some View {
        if isLive {
            Circle()
                .fill(model.state == .playing ? Color.adSuccess : Color.adWarning)
                .frame(width: 5, height: 5)
        }
    }
}

// MARK: - Cyberdeck Player Popover View

public struct CyberdeckPlayerPopoverView: View {
    @Bindable var model: CyberdeckPlayerModel

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "headphones")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.cyan)

                    Text("CYBERDECK VIBE STATION")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.adTextPrimary)
                }

                Spacer()

                // State Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(model.state == .playing ? Color.adSuccess : (model.state == .error ? Color.adError : Color.adTextTertiary))
                        .frame(width: 6, height: 6)

                    Text(model.state.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.adTextSecondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.adElevated)
                .clipShape(Capsule())
            }

            // Now Playing Card
            VStack(alignment: .leading, spacing: 6) {
                Text(model.currentStation?.tag ?? "AUDIO STREAM")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cyan)

                Text(model.currentTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.adTextPrimary)
                    .lineLimit(2)

                if let err = model.errorMessage {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adError)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.adNavy)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.adDivider, lineWidth: 1)
            )

            // Playback Controls & Volume
            HStack(spacing: 14) {
                // Play / Pause Button
                Button {
                    model.togglePlayPause()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(model.state == .playing ? "Pause" : "Play")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.cyan)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                // Stop Button
                Button {
                    model.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                        .padding(7)
                        .background(Color.adElevated)
                        .foregroundStyle(Color.adTextSecondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop Radio")

                Spacer()

                // Volume Slider with Mute
                HStack(spacing: 6) {
                    Button {
                        model.isMuted.toggle()
                    } label: {
                        Image(systemName: model.isMuted || model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.adTextSecondary)
                    }
                    .buttonStyle(.plain)

                    Slider(value: $model.volume, in: 0.0...1.0)
                        .frame(width: 70)
                        .tint(Color.cyan)
                }
            }

            Divider()
                .foregroundStyle(Color.adDivider)

            // Preset Stations Grid
            VStack(alignment: .leading, spacing: 6) {
                Text("PRESET STATIONS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)

                VStack(spacing: 4) {
                    ForEach(CyberStation.presets) { station in
                        let isCurrent = model.currentStation?.id == station.id
                        Button {
                            model.playStation(station)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: station.iconName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: station.accentColorHex))
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(station.name)
                                        .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                                        .foregroundStyle(isCurrent ? Color.adTextPrimary : Color.adTextSecondary)
                                    Text(station.tag)
                                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.adTextTertiary)
                                }

                                Spacer()

                                if isCurrent && model.state == .playing {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.cyan)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(isCurrent ? Color.adOverlay : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
                .foregroundStyle(Color.adDivider)

            // Custom YouTube Link Input Field
            VStack(alignment: .leading, spacing: 6) {
                Text("CUSTOM YOUTUBE STREAM")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.adTextTertiary)

                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(Color.adTextTertiary)

                    TextField("Paste YouTube URL / Stream link...", text: $model.customUrlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit {
                            model.playYouTube(url: model.customUrlInput)
                        }

                    if !model.customUrlInput.isEmpty {
                        Button("Stream") {
                            model.playYouTube(url: model.customUrlInput)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan)
                        .foregroundStyle(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Color.adBackground)
    }
}

// DictationService.swift
// AdventurersCore — WhisperKit-native Dictation & Audio Pipeline
// Uses on-device Whisper via WhisperKit (Apple Silicon Neural Engine optimized).
// Records audio to WAV, then transcribes with WhisperKit — no Python, no cloud.

import Foundation
import AVFoundation
import Combine
import os.lock
import WhisperKit

// MARK: - Smart Spoken Punctuation Formatter

public struct DictationPunctuationFormatter: Sendable {
    public init() {}

    public func format(rawText: String) -> String {
        guard !rawText.isEmpty else { return "" }

        var result = rawText

        let replacements: [(pattern: String, replacement: String)] = [
            (#"\bnew line\b"#, "\n"),
            (#"\bnewline\b"#, "\n"),
            (#"\bnext line\b"#, "\n"),
            (#"\bperiod\b"#, "."),
            (#"\bfull stop\b"#, "."),
            (#"\bcomma\b"#, ","),
            (#"\bquestion mark\b"#, "?"),
            (#"\bexclamation mark\b"#, "!"),
            (#"\bexclamation point\b"#, "!"),
            (#"\bcolon\b"#, ":"),
            (#"\bsemicolon\b"#, ";"),
            (#"\bopen parenthesis\b"#, "("),
            (#"\bclose parenthesis\b"#, ")"),
            (#"\bopen paren\b"#, "("),
            (#"\bclose paren\b"#, ")"),
            (#"\bopen bracket\b"#, "["),
            (#"\bclose bracket\b"#, "]"),
            (#"\bopen brace\b"#, "{"),
            (#"\bclose brace\b"#, "}"),
            (#"\bcode block\b"#, "```"),
            (#"\bbacktick\b"#, "`"),
            (#"\bdot\b"#, "."),
            (#"\barrow\b"#, "->"),
            (#"\bunderscore\b"#, "_"),
            (#"\bhyphen\b"#, "-")
        ]

        for (pattern, replacement) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }

        let cleanPunctuationPatterns: [(pattern: String, replacement: String)] = [
            (#"\s+([.,!?:;)])"#, "$1"),
            (#"([(])\s+"#, "$1"),
            (#"([a-zA-Z0-9_]+)\s+\("#, "$1("),
            (#"\n\s+"#, "\n")
        ]

        for (pattern, replacement) in cleanPunctuationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: replacement
                )
            }
        }

        result = capitalizeSentences(result)

        return result.trimmingCharacters(in: .whitespaces)
    }

    private func capitalizeSentences(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var output = ""
        var capitalizeNext = true

        for char in text {
            if capitalizeNext && char.isLetter {
                output.append(char.uppercased())
                capitalizeNext = false
            } else {
                output.append(char)
                if char == "." || char == "!" || char == "?" || char == "\n" {
                    capitalizeNext = true
                }
            }
        }

        return output
    }
}

// MARK: - Thread-Safe Audio Tap Handler (Talkies Pattern)

public final class DictationAudioTapHandler: @unchecked Sendable {
    private var _level: Float = 0.0
    private let lock = OSAllocatedUnfairLock()
    let audioFile: AVAudioFile?

    public init(audioFile: AVAudioFile? = nil) {
        self.audioFile = audioFile
    }

    public var level: Float {
        get { lock.withLock { _level } }
        set { lock.withLock { _level = newValue } }
    }

    public func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        // Write buffer to file
        try? audioFile?.write(from: buffer)

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        let sumSquares = channelDataArray.reduce(0.0) { $0 + ($1 * $1) }
        let rms = sqrt(sumSquares / Float(frameCount))

        let db = 20 * log10(max(rms, 0.0001))
        let normalized = min(max((db + 60) / 60, 0.0), 1.0)

        level = normalized
    }

    nonisolated static func installTap(on inputNode: AVAudioInputNode, format: AVAudioFormat?, handler: DictationAudioTapHandler) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            handler.handleBuffer(buffer)
        }
    }
}

// MARK: - Dictation Engine State

public enum DictationState: Sendable, Equatable {
    case idle
    case listening
    case processing
    case error(String)

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

// MARK: - Dictation Manager (Main Actor, WhisperKit-backed)

@MainActor
public final class DictationManager: NSObject, ObservableObject {
    public static let shared = DictationManager()

    @Published public var state: DictationState = .idle
    @Published public var audioLevel: Float = 0.0
    @Published public var liveTranscript: String = ""
    @Published public var hasMicrophonePermission: Bool = false
    /// True once the on-device Whisper model has finished loading/downloading. Replaces the old
    /// SFSpeechRecognizer authorization flag — WhisperKit needs no speech permission, only mic.
    @Published public var isWhisperReady: Bool = false

    // User-configurable dictation behavior (synced from SettingsModel via applySettings).
    private var silenceTimeout: TimeInterval = 4.5
    private var autoPunctuation: Bool = true
    private var speechLanguage: String = "en-US"
    /// Timestamp of the last audio frame above the voice-activity threshold (drives silence auto-commit).
    private var lastVoiceActivityAt: Date = Date()

    public func applySettings(silenceTimeout: TimeInterval, autoPunctuation: Bool, language: String) {
        self.silenceTimeout = max(1.5, silenceTimeout)
        self.autoPunctuation = autoPunctuation
        self.speechLanguage = language
    }

    private var audioEngine: AVAudioEngine?
    private var tapHandler: DictationAudioTapHandler?
    private let formatter = DictationPunctuationFormatter()
    private var levelTimer: Timer?
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var prefixText: String = ""
    private var onTextUpdate: (@Sendable (String) -> Void)?

    nonisolated(unsafe) private var whisperKit: WhisperKit?
    private var isWhisperInitialized = false
    private var isTranscribing = false
    private var whisperModel: String = "openai_whisper-base"

    public init(locale: Locale = Locale(identifier: "en-US")) {
        super.init()
        Task {
            await initializeWhisperKit()
        }
    }

    // MARK: - WhisperKit Initialization

    private func initializeWhisperKit() async {
        do {
            whisperKit = try await WhisperKit(
                model: whisperModel,
                verbose: false,
                logLevel: .info
            )
            isWhisperInitialized = true
            isWhisperReady = true
            print("[DictationService] WhisperKit initialized with model: \(whisperModel)")
        } catch {
            print("[DictationService] WhisperKit init failed: \(error)")
            // Retry with tiny model as fallback
            do {
                whisperKit = try await WhisperKit(
                    model: "openai_whisper-tiny",
                    verbose: false,
                    logLevel: .info
                )
                isWhisperInitialized = true
                isWhisperReady = true
                print("[DictationService] WhisperKit fallback to tiny model succeeded")
            } catch {
                print("[DictationService] WhisperKit fallback also failed: \(error)")
            }
        }
    }

    // MARK: - Permission Verification

    public func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.hasMicrophonePermission = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    self.hasMicrophonePermission = granted
                }
            }
        default:
            self.hasMicrophonePermission = false
        }
    }

    // MARK: - Dictation Control

    public func toggleDictation(currentText: String, onUpdate: @escaping @Sendable (String) -> Void) {
        if isTranscribing { return }
        if state.isListening {
            stopAndTranscribe()
        } else {
            startDictation(initialText: currentText, onUpdate: onUpdate)
        }
    }

    public func startDictation(initialText: String, onUpdate: @escaping @Sendable (String) -> Void) {
        guard !state.isListening else { return }

        self.prefixText = initialText.trimmingCharacters(in: .whitespaces)
        self.onTextUpdate = onUpdate
        self.liveTranscript = ""

        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.hasMicrophonePermission = granted
                    if granted {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            self.startDictation(initialText: initialText, onUpdate: onUpdate)
                        }
                    } else {
                        self.state = .error("Microphone permission denied.")
                    }
                }
            }
            return
        } else if micStatus != .authorized {
            self.state = .error("Microphone permission denied. Enable in System Settings -> Privacy -> Microphone.")
            return
        }

        // Ensure WhisperKit is ready
        guard isWhisperInitialized, let _ = whisperKit else {
            self.state = .error("Whisper model still loading. Please wait...")
            Task { await initializeWhisperKit() }
            return
        }

        do {
            stopCleanup()

            let engine = AVAudioEngine()
            self.audioEngine = engine

            let inputNode = engine.inputNode
            let nativeFormat = inputNode.outputFormat(forBus: 0)

            let sampleRate = nativeFormat.sampleRate
            let channels = nativeFormat.channelCount
            guard sampleRate > 0 && channels > 0 else {
                state = .error("Microphone hardware is busy or sample rate is uninitialized.")
                return
            }

            // Create temp WAV file for recording
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("dictation_\(UUID().uuidString).wav")
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: nativeFormat.settings)
            self.audioFile = audioFile
            self.audioFileURL = fileURL

            // Install tap with thread-safe handler (Talkies pattern)
            let handler = DictationAudioTapHandler(audioFile: audioFile)
            self.tapHandler = handler
            DictationAudioTapHandler.installTap(on: inputNode, format: nativeFormat, handler: handler)

            engine.prepare()
            try engine.start()

            state = .listening
            startLevelTimer()
        } catch {
            state = .error("Audio engine error: \(error.localizedDescription)")
            stopCleanup()
        }
    }

    public func stopDictation() {
        guard state.isListening || audioEngine != nil else { return }
        stopAndTranscribe()
    }

    // MARK: - Stop Recording & Transcribe with WhisperKit

    private func stopAndTranscribe() {
        guard state.isListening || audioEngine != nil else { return }

        let fileURL = self.audioFileURL

        // Stop audio engine
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
        }

        audioEngine = nil
        tapHandler = nil
        audioFile = nil
        stopLevelTimer()

        guard let audioURL = fileURL else {
            state = .idle
            return
        }

        // Transcribe with WhisperKit
        state = .processing
        isTranscribing = true
        let wk = self.whisperKit
        let capturedPrefix = self.prefixText
        let capturedFormatter = self.formatter
        let useFormatter = self.autoPunctuation
        let languageCode = Self.whisperLanguageCode(from: self.speechLanguage)
        let baseUpdate = self.onTextUpdate
        let capturedOnUpdate: @Sendable (String, String) -> Void = { [weak self] formatted, full in
            Task { @MainActor in
                self?.liveTranscript = formatted
                baseUpdate?(full)
            }
        }
        Task {
            let failure = await Self.transcribeWithWhisperKit(audioURL: audioURL, whisperKit: wk, prefixText: capturedPrefix, formatter: capturedFormatter, applyPunctuation: useFormatter, language: languageCode, onUpdate: capturedOnUpdate)
            await MainActor.run {
                self.isTranscribing = false
                self.audioLevel = 0.0
                self.state = failure.map { .error($0) } ?? .idle
            }
        }
    }

    /// Maps a BCP-47 locale identifier (e.g. "en-US") to Whisper's language code ("en").
    /// Returns nil for "auto" / unknown — letting Whisper auto-detect.
    private static func whisperLanguageCode(from localeID: String) -> String? {
        let trimmed = localeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "auto" else { return nil }
        return trimmed.split(separator: "-").first.map(String.init)
    }

    /// Returns nil on success, or a user-presentable error message on failure.
    private static func transcribeWithWhisperKit(audioURL: URL, whisperKit wk: sending WhisperKit?, prefixText: String, formatter: DictationPunctuationFormatter, applyPunctuation: Bool, language: String?, onUpdate: (@Sendable (String, String) -> Void)?) async -> String? {
        guard let wk else { return "Speech model still loading. Try again in a moment." }

        do {
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: language,
                temperature: 0.0,
                temperatureIncrementOnFallback: 0.2,
                temperatureFallbackCount: 5,
                sampleLength: 224,
                topK: 5,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                clipTimestamps: [0]
            )

            let results = try await wk.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            )

            let transcribedText: String = results.flatMap { result in
                result.segments.map { $0.text }
            }.joined(separator: " ")

            let formattedText = applyPunctuation
                ? formatter.format(rawText: transcribedText)
                : transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                // Nothing captured — don't clobber existing prompt text with an empty append.
                guard !formattedText.isEmpty else {
                    try? FileManager.default.removeItem(at: audioURL)
                    return
                }
                let fullText: String
                if prefixText.isEmpty {
                    fullText = formattedText
                } else {
                    fullText = "\(prefixText) \(formattedText)"
                }
                onUpdate?(formattedText, fullText)
                try? FileManager.default.removeItem(at: audioURL)
            }
            return nil
        } catch {
            print("[DictationService] Transcription error: \(error)")
            await MainActor.run {
                try? FileManager.default.removeItem(at: audioURL)
            }
            return "Transcription failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Cleanup

    private func stopCleanup() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
        }
        audioEngine = nil
        tapHandler = nil
        audioFile = nil
        stopLevelTimer()
        audioLevel = 0.0
    }

    // MARK: - Level Timer (metering + voice-activity-driven silence auto-commit)

    /// RMS level above which audio counts as speech for the silence timeout.
    private static let voiceActivityThreshold: Float = 0.08

    private func startLevelTimer() {
        levelTimer?.invalidate()
        let handler = self.tapHandler
        lastVoiceActivityAt = Date()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            let targetLevel = handler?.level ?? 0.0
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.audioLevel = self.audioLevel * 0.4 + targetLevel * 0.6

                guard self.state.isListening else { return }

                if targetLevel >= Self.voiceActivityThreshold {
                    self.lastVoiceActivityAt = Date()
                } else if Date().timeIntervalSince(self.lastVoiceActivityAt) >= self.silenceTimeout {
                    // Unbroken silence for the configured duration — auto-commit the transcript.
                    self.stopAndTranscribe()
                }
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}

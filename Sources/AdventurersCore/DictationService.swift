// DictationService.swift
// AdventurersCore — Minimal Pure Swift Speech Dictation & Audio Pipeline
// Inspired by Talkies macOS audio engine with real-time streaming recognition,
// RMS audio level metering, silence detection, and smart punctuation formatting.

import Foundation
import AVFoundation
import Speech
import Combine
import os.lock

// MARK: - Smart Spoken Punctuation Formatter

public struct DictationPunctuationFormatter: Sendable {
    public init() {}

    /// Formats spoken transcription by mapping spoken punctuation words to symbols and capitalizing sentences.
    public func format(rawText: String) -> String {
        guard !rawText.isEmpty else { return "" }

        var result = rawText

        // Punctuation replacements (case-insensitive)
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

        // Clean up accidental spaces before punctuation (e.g., "Hello , world ." -> "Hello, world.")
        let cleanPunctuationPatterns: [(pattern: String, replacement: String)] = [
            (#"\s+([.,!?:;)])"#, "$1"),
            (#"([(])\s+"#, "$1"),
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

        // Sentence capitalization
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

// MARK: - Thread-Safe Audio Tap Handler (Talkies Port)

public final class DictationAudioTapHandler: @unchecked Sendable {
    private var _level: Float = 0.0
    private let lock = OSAllocatedUnfairLock()

    public init() {}

    public var level: Float {
        get { lock.withLock { _level } }
        set { lock.withLock { _level = newValue } }
    }

    public func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        let sumSquares = channelDataArray.reduce(0.0) { $0 + ($1 * $1) }
        let rms = sqrt(sumSquares / Float(frameCount))

        // Decibel normalization (-60dB to 0dB -> 0.0 to 1.0)
        let db = 20 * log10(max(rms, 0.0001))
        let normalized = min(max((db + 60) / 60, 0.0), 1.0)

        level = normalized
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

// MARK: - Dictation Manager (Main Actor)

@MainActor
public final class DictationManager: ObservableObject {
    public static let shared = DictationManager()

    @Published public var state: DictationState = .idle
    @Published public var audioLevel: Float = 0.0
    @Published public var liveTranscript: String = ""
    @Published public var hasMicrophonePermission: Bool = false
    @Published public var hasSpeechPermission: Bool = false

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let tapHandler = DictationAudioTapHandler()
    private let formatter = DictationPunctuationFormatter()
    private var levelTimer: Timer?
    private var silenceTimer: Timer?
    private var prefixText: String = ""
    private var onTextUpdate: ((String) -> Void)?

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
        checkPermissions()
    }

    // MARK: - Permission Verification

    public func checkPermissions() {
        // Microphone permission
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

        // Speech recognition permission
        SFSpeechRecognizer.requestAuthorization { authStatus in
            Task { @MainActor in
                self.hasSpeechPermission = (authStatus == .authorized)
            }
        }
    }

    // MARK: - Dictation Control

    public func toggleDictation(currentText: String, onUpdate: @escaping (String) -> Void) {
        if state.isListening {
            stopDictation()
        } else {
            startDictation(initialText: currentText, onUpdate: onUpdate)
        }
    }

    public func startDictation(initialText: String, onUpdate: @escaping (String) -> Void) {
        guard !state.isListening else { return }

        // Store baseline text to append smoothly
        self.prefixText = initialText.trimmingCharacters(in: .whitespaces)
        self.onTextUpdate = onUpdate
        self.liveTranscript = ""

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("Speech recognizer unavailable on this system")
            return
        }

        do {
            let engine = AVAudioEngine()
            self.audioEngine = engine

            let node = engine.inputNode
            let recordingFormat = node.outputFormat(forBus: 0)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            self.recognitionRequest = request

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let formattedSpoken = self.formatter.format(rawText: result.bestTranscription.formattedString)
                    self.liveTranscript = formattedSpoken

                    let fullText: String
                    if self.prefixText.isEmpty {
                        fullText = formattedSpoken
                    } else {
                        fullText = "\(self.prefixText) \(formattedSpoken)"
                    }

                    self.onTextUpdate?(fullText)
                    self.resetSilenceTimer()
                }

                if error != nil || (result?.isFinal ?? false) {
                    self.stopDictation()
                }
            }

            node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                self?.tapHandler.handleBuffer(buffer)
            }

            engine.prepare()
            try engine.start()

            state = .listening
            startLevelTimer()
            resetSilenceTimer()
        } catch {
            state = .error("Audio engine failed: \(error.localizedDescription)")
            stopDictation()
        }
    }

    public func stopDictation() {
        guard state.isListening || state == .processing else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        stopLevelTimer()
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioLevel = 0.0
        state = .idle
    }

    // MARK: - Level & Silence Timers

    private func startLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let targetLevel = self.tapHandler.level
            // Smooth lerp
            self.audioLevel = self.audioLevel * 0.4 + targetLevel * 0.6
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        // Auto-commit and pause after 4.5 seconds of unbroken silence
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            self?.stopDictation()
        }
    }
}

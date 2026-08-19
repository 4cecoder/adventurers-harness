// DictationTests.swift
// Adventurers Harness — Talkies Dictation Pipeline, Punctuation Formatting & Audio Level Metering Tests

import Testing
import Foundation
import AVFoundation
@testable import AdventurersCore

@Suite("Dictation & Audio Pipeline Suite")
struct DictationTests {

    // MARK: - Smart Punctuation Formatter

    @Test("Dictation Punctuation Formatter replaces spoken punctuation symbols")
    func punctuationReplacements() {
        let formatter = DictationPunctuationFormatter()

        let rawSpoken = "hello world comma please create a swift struct period new line next line thank you question mark"
        let formatted = formatter.format(rawText: rawSpoken)

        #expect(formatted.contains("Hello world,"))
        #expect(formatted.contains("struct."))
        #expect(formatted.contains("\n"))
        #expect(formatted.contains("Thank you?"))
    }

    @Test("Dictation Punctuation Formatter handles code and developer symbols")
    func codePunctuationReplacements() {
        let formatter = DictationPunctuationFormatter()

        let raw = "function add open paren a colon int comma b colon int close paren arrow int code block return a plus b"
        let formatted = formatter.format(rawText: raw)

        #expect(formatted.contains("add(a: Int, b: Int) -> Int"))
        #expect(formatted.contains("```"))
    }

    @Test("Dictation Punctuation Formatter cleans up leading and trailing whitespace around punctuation")
    func whitespaceCleanup() {
        let formatter = DictationPunctuationFormatter()

        let raw = "clean this up , please . and that !"
        let formatted = formatter.format(rawText: raw)

        #expect(formatted.contains("Clean this up, please. And that!"))
        #expect(!formatted.contains(" ,"))
        #expect(!formatted.contains(" ."))
    }

    // MARK: - Thread-Safe Audio Tap Metering

    @Test("Dictation Audio Tap Handler calculates normalized RMS decibel levels")
    func audioTapHandlerRMS() {
        let handler = DictationAudioTapHandler()
        #expect(handler.level == 0.0)

        // Create mock PCM Buffer with silence
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        silentBuffer.frameLength = 1024
        handler.handleBuffer(silentBuffer)
        #expect(handler.level >= 0.0)

        // Create mock PCM Buffer with non-zero audio values
        let loudBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        loudBuffer.frameLength = 1024
        if let channelData = loudBuffer.floatChannelData?[0] {
            for i in 0..<1024 {
                channelData[i] = 0.5 * sin(Float(i) * 0.1)
            }
        }
        handler.handleBuffer(loudBuffer)
        #expect(handler.level > 0.0)
    }

    // MARK: - Dictation Manager State

    @Test("Dictation Manager initializes cleanly in idle state")
    @MainActor
    func dictationManagerInitialization() {
        let manager = DictationManager.shared
        #expect(manager.state == .idle)
        #expect(manager.audioLevel == 0.0)
        #expect(manager.liveTranscript.isEmpty)
    }
}

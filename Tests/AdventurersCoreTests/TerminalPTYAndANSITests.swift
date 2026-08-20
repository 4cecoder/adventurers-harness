// TerminalPTYAndANSITests.swift
// AdventurersCoreTests — Unit Tests for Native PTY & Streamed ANSI/VT100 Engine

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Terminal POSIX PTY & Streamed ANSI Parser Suite")
struct TerminalPTYAndANSITests {

    @Test("ANSI Parser extracts standard 16 colors and styles")
    func parseStandardANSIColors() {
        let input = "\u{1B}[31;1mRed Bold Text\u{1B}[0m and \u{1B}[32mGreen Text\u{1B}[0m"
        let spans = TerminalANSIParser.parse(input)
        #expect(spans.count >= 3)

        // First span: Red & Bold
        #expect(spans[0].text == "Red Bold Text")
        #expect(spans[0].style.isBold == true)
        #expect(spans[0].style.foregroundColor == .standard(.red))

        // Third span: Green
        #expect(spans[2].text == "Green Text")
        #expect(spans[2].style.foregroundColor == .standard(.green))
    }

    @Test("ANSI Parser handles 256-color palette and 24-bit TrueColor")
    func parseExtendedANSIColors() {
        // 256-color foreground (color 196 = bright red)
        let input256 = "\u{1B}[38;5;196m256 Color Text\u{1B}[0m"
        let spans256 = TerminalANSIParser.parse(input256)
        #expect(spans256.count >= 1)
        #expect(spans256[0].style.foregroundColor == .index256(196))

        // 24-bit TrueColor (RGB: 255, 100, 50)
        let inputTrueColor = "\u{1B}[38;2;255;100;50mTrueColor Text\u{1B}[0m"
        let spansTrue = TerminalANSIParser.parse(inputTrueColor)
        #expect(spansTrue.count >= 1)
        #expect(spansTrue[0].style.foregroundColor == .trueColor(r: 255, g: 100, b: 50))
    }

    @Test("ANSI Parser strips escape sequences accurately")
    func stripANSIEscapeSequences() {
        let input = "\u{1B}[1;34mAdventurers\u{1B}[0m \u{1B}[32mHarness\u{1B}[0m"
        let stripped = TerminalANSIParser.stripANSI(input)
        #expect(stripped == "Adventurers Harness")
    }

    @Test("POSIX PTY allocates master/slave file descriptors and resizes window")
    func ptyAllocationAndResize() throws {
        let pty = try TerminalPTY(windowSize: TerminalWindowSize(cols: 120, rows: 40))
        #expect(pty.masterFD >= 0)
        #expect(pty.slaveFD >= 0)
        #expect(pty.windowSize.cols == 120)
        #expect(pty.windowSize.rows == 40)

        // Test dynamic resize (TIOCSWINSZ)
        try pty.resize(cols: 160, rows: 50)
        #expect(pty.windowSize.cols == 160)
        #expect(pty.windowSize.rows == 50)

        pty.closePTY()
    }
}

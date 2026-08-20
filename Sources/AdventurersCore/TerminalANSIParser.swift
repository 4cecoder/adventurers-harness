// TerminalANSIParser.swift
// AdventurersCore — High-Performance Streamed ANSI & VT100 Escape Sequence Parser
// Supports: 16 ANSI colors, 256-color palette, 24-bit RGB TrueColor, styles (bold, italic, underline, inverse), and cursor controls.

import Foundation

// MARK: - ANSI Style Model

public struct ANSITextStyle: Sendable, Equatable {
    public var isBold: Bool = false
    public var isDim: Bool = false
    public var isItalic: Bool = false
    public var isUnderline: Bool = false
    public var isInverse: Bool = false
    public var foregroundColor: ANSIColor?
    public var backgroundColor: ANSIColor?

    public init(
        isBold: Bool = false,
        isDim: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isInverse: Bool = false,
        foregroundColor: ANSIColor? = nil,
        backgroundColor: ANSIColor? = nil
    ) {
        self.isBold = isBold
        self.isDim = isDim
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isInverse = isInverse
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
    }

    public mutating func reset() {
        self.isBold = false
        self.isDim = false
        self.isItalic = false
        self.isUnderline = false
        self.isInverse = false
        self.foregroundColor = nil
        self.backgroundColor = nil
    }
}

// MARK: - ANSI Color Model

public enum ANSIColor: Sendable, Equatable {
    case standard(ANSIStandardColor)
    case index256(UInt8)
    case trueColor(r: UInt8, g: UInt8, b: UInt8)

    public var hexString: String {
        switch self {
        case .standard(let std):
            return std.hexValue
        case .index256(let idx):
            return ANSIStandardColor.colorFor256(idx)
        case .trueColor(let r, let g, let b):
            return String(format: "#%02X%02X%02X", r, g, b)
        }
    }
}

public enum ANSIStandardColor: Int, Sendable, Equatable {
    case black = 0
    case red = 1
    case green = 2
    case yellow = 3
    case blue = 4
    case magenta = 5
    case cyan = 6
    case white = 7
    case brightBlack = 8
    case brightRed = 9
    case brightGreen = 10
    case brightYellow = 11
    case brightBlue = 12
    case brightMagenta = 13
    case brightCyan = 14
    case brightWhite = 15

    public var hexValue: String {
        switch self {
        case .black: return "#1E1E1E"
        case .red: return "#FF5C57"
        case .green: return "#5AF78E"
        case .yellow: return "#F3F99D"
        case .blue: return "#57C7FF"
        case .magenta: return "#FF6AC1"
        case .cyan: return "#9AEDFE"
        case .white: return "#F1F1F0"
        case .brightBlack: return "#686868"
        case .brightRed: return "#FF5C57"
        case .brightGreen: return "#5AF78E"
        case .brightYellow: return "#F3F99D"
        case .brightBlue: return "#57C7FF"
        case .brightMagenta: return "#FF6AC1"
        case .brightCyan: return "#9AEDFE"
        case .brightWhite: return "#FFFFFF"
        }
    }

    public static func colorFor256(_ idx: UInt8) -> String {
        if idx < 16 {
            return ANSIStandardColor(rawValue: Int(idx))?.hexValue ?? "#FFFFFF"
        }
        if idx >= 232 {
            // Grayscale ramp
            let gray = Int(idx - 232) * 10 + 8
            return String(format: "#%02X%02X%02X", gray, gray, gray)
        }
        // 6x6x6 color cube
        let colorIdx = Int(idx - 16)
        let r = (colorIdx / 36) * 51
        let g = ((colorIdx % 36) / 6) * 51
        let b = (colorIdx % 6) * 51
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Styled ANSI Span

public struct ANSISpan: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let style: ANSITextStyle

    public init(id: UUID = UUID(), text: String, style: ANSITextStyle) {
        self.id = id
        self.text = text
        self.style = style
    }
}

// MARK: - Streamed ANSI Parser

public struct TerminalANSIParser: Sendable {
    public init() {}

    /// Parses raw ANSI escape string into a collection of styled text spans
    public static func parse(_ input: String) -> [ANSISpan] {
        var spans: [ANSISpan] = []
        var currentStyle = ANSITextStyle()
        var currentBuffer = ""

        let scalars = Array(input.unicodeScalars)
        var idx = 0

        while idx < scalars.count {
            let scalar = scalars[idx]

            // Check for Escape character (0x1B or \u{1B})
            if scalar.value == 0x1B && idx + 1 < scalars.count {
                let nextScalar = scalars[idx + 1]
                if nextScalar.value == 0x5B { // '[' CSI (Control Sequence Introducer)
                    // Flush existing buffer
                    if !currentBuffer.isEmpty {
                        spans.append(ANSISpan(text: currentBuffer, style: currentStyle))
                        currentBuffer = ""
                    }

                    // Parse CSI sequence
                    var csiEnd = idx + 2
                    while csiEnd < scalars.count {
                        let ch = scalars[csiEnd].value
                        // CSI terminates on byte between 0x40 ('@') and 0x7E ('~')
                        if ch >= 0x40 && ch <= 0x7E {
                            break
                        }
                        csiEnd += 1
                    }

                    if csiEnd < scalars.count {
                        let finalChar = scalars[csiEnd]
                        let paramSlice = scalars[(idx + 2)..<csiEnd]
                        let paramString = String(String.UnicodeScalarView(paramSlice))

                        if finalChar == "m" { // SGR (Select Graphic Rendition)
                            applySGR(params: paramString, style: &currentStyle)
                        }
                        idx = csiEnd + 1
                        continue
                    }
                }
            }

            // Normal text character
            currentBuffer.append(Character(scalar))
            idx += 1
        }

        if !currentBuffer.isEmpty {
            spans.append(ANSISpan(text: currentBuffer, style: currentStyle))
        }

        return spans
    }

    /// Strips all ANSI codes from a string to yield pure plain text
    public static func stripANSI(_ input: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, range: range, withTemplate: "")
    }

    private static func applySGR(params: String, style: inout ANSITextStyle) {
        if params.isEmpty || params == "0" {
            style.reset()
            return
        }

        let parts = params.components(separatedBy: ";").compactMap { Int($0) }
        var i = 0

        while i < parts.count {
            let code = parts[i]

            switch code {
            case 0:
                style.reset()
            case 1:
                style.isBold = true
            case 2:
                style.isDim = true
            case 3:
                style.isItalic = true
            case 4:
                style.isUnderline = true
            case 7:
                style.isInverse = true
            case 22:
                style.isBold = false
                style.isDim = false
            case 23:
                style.isItalic = false
            case 24:
                style.isUnderline = false
            case 27:
                style.isInverse = false
            case 30...37:
                if let std = ANSIStandardColor(rawValue: code - 30) {
                    style.foregroundColor = .standard(std)
                }
            case 38: // Extended foreground (256-color or 24-bit TrueColor)
                if i + 1 < parts.count {
                    if parts[i + 1] == 5 && i + 2 < parts.count { // 38;5;N
                        style.foregroundColor = .index256(UInt8(clamping: parts[i + 2]))
                        i += 2
                    } else if parts[i + 1] == 2 && i + 4 < parts.count { // 38;2;R;G;B
                        style.foregroundColor = .trueColor(
                            r: UInt8(clamping: parts[i + 2]),
                            g: UInt8(clamping: parts[i + 3]),
                            b: UInt8(clamping: parts[i + 4])
                        )
                        i += 4
                    }
                }
            case 39:
                style.foregroundColor = nil
            case 40...47:
                if let std = ANSIStandardColor(rawValue: code - 40) {
                    style.backgroundColor = .standard(std)
                }
            case 48: // Extended background (256-color or 24-bit TrueColor)
                if i + 1 < parts.count {
                    if parts[i + 1] == 5 && i + 2 < parts.count { // 48;5;N
                        style.backgroundColor = .index256(UInt8(clamping: parts[i + 2]))
                        i += 2
                    } else if parts[i + 1] == 2 && i + 4 < parts.count { // 48;2;R;G;B
                        style.backgroundColor = .trueColor(
                            r: UInt8(clamping: parts[i + 2]),
                            g: UInt8(clamping: parts[i + 3]),
                            b: UInt8(clamping: parts[i + 4])
                        )
                        i += 4
                    }
                }
            case 49:
                style.backgroundColor = nil
            case 90...97: // Bright foregrounds
                if let std = ANSIStandardColor(rawValue: code - 90 + 8) {
                    style.foregroundColor = .standard(std)
                }
            case 100...107: // Bright backgrounds
                if let std = ANSIStandardColor(rawValue: code - 100 + 8) {
                    style.backgroundColor = .standard(std)
                }
            default:
                break
            }
            i += 1
        }
    }
}

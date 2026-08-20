// TerminalANSIView.swift
// Adventurers GUI — High-Fidelity Terminal ANSI Output Staging & Stream Renderer
// Displays ANSI 256-color & TrueColor styled spans with monospaced typography and selection.

import SwiftUI
import AdventurersCore

public struct TerminalANSIView: View {
    public let rawContent: String
    public let fontSize: CGFloat

    public init(rawContent: String, fontSize: CGFloat = 11) {
        self.rawContent = rawContent
        self.fontSize = fontSize
    }

    public var body: some View {
        let spans = TerminalANSIParser.parse(rawContent)
        HStack(spacing: 0) {
            ForEach(spans) { span in
                styledSpanText(span)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func styledSpanText(_ span: ANSISpan) -> some View {
        let fgColor: Color = {
            if let fg = span.style.foregroundColor {
                return Color(hex: fg.hexString)
            }
            return Color.adTextPrimary
        }()

        let bgColor: Color = {
            if let bg = span.style.backgroundColor {
                return Color(hex: bg.hexString)
            }
            return Color.clear
        }()

        Text(span.text)
            .font(.system(size: fontSize, weight: span.style.isBold ? .bold : .regular, design: .monospaced))
            .italic(span.style.isItalic)
            .underline(span.style.isUnderline, color: fgColor)
            .foregroundStyle(span.style.isDim ? fgColor.opacity(0.6) : fgColor)
            .background(bgColor)
    }
}

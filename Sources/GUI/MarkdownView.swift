// MarkdownView.swift
// Adventurers GUI — Pure Swift 6 Native Markdown Element Parser & High-Fidelity Renderer
// Supports: Headers (#..####), Bullet Lists, Numbered Lists, Task Lists, Blockquotes, Tables, Dividers, and AttributedString Inline Markdown

import SwiftUI
import AdventurersCore

// MARK: - Native Markdown Block View

public struct MarkdownBlockView: View {
    public let element: MarkdownElement
    public let onCopyCode: (String) -> Void

    public init(element: MarkdownElement, onCopyCode: @escaping (String) -> Void = { _ in }) {
        self.element = element
        self.onCopyCode = onCopyCode
    }

    public var body: some View {
        switch element {
        case .header(let level, let text, _):
            headerView(level: level, text: text)

        case .paragraph(let text, _):
            inlineFormattedText(text)
                .lineSpacing(3)

        case .bulletList(let items, _):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.adOrange)
                            .frame(width: 10, alignment: .center)
                        inlineFormattedText(item)
                    }
                }
            }
            .padding(.leading, 4)

        case .numberedList(let items, _):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.number) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(item.number).")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.cyan)
                            .frame(minWidth: 16, alignment: .trailing)
                        inlineFormattedText(item.text)
                    }
                }
            }
            .padding(.leading, 4)

        case .taskList(let items, _):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11))
                            .foregroundStyle(item.isDone ? Color.adSuccess : Color.adTextTertiary)
                            .frame(width: 14)
                        inlineFormattedText(item.text)
                            .strikethrough(item.isDone, color: Color.adTextTertiary)
                            .foregroundStyle(item.isDone ? Color.adTextTertiary : Color.adTextPrimary)
                    }
                }
            }
            .padding(.leading, 4)

        case .blockquote(let text, _):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.adOrange.opacity(0.8))
                    .frame(width: 3)

                inlineFormattedText(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.adTextSecondary)
                    .italic()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 4))

        case .table(let headers, let rows, _):
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { idx, h in
                        Text(h)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.adTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                        if idx < headers.count - 1 {
                            Divider().frame(height: 16)
                        }
                    }
                }
                .background(Color.adElevated)

                Divider()

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { cIdx, cell in
                            Text(cell)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.adTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                            if cIdx < row.count - 1 {
                                Divider().frame(height: 14)
                            }
                        }
                    }
                    .background(rIdx % 2 == 0 ? Color.clear : Color.white.opacity(0.02))
                    if rIdx < rows.count - 1 {
                        Divider().foregroundStyle(Color.white.opacity(0.05))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.adDivider, lineWidth: 1))

        case .divider:
            Divider()
                .foregroundStyle(Color.adDivider)
                .padding(.vertical, 4)

        case .codeBlock(let language, let code, let id):
            CodeBlockView(
                language: language,
                code: code,
                isCopied: false
            ) {
                onCopyCode(code)
            }
        }
    }

    @ViewBuilder
    private func headerView(level: Int, text: String) -> some View {
        switch level {
        case 1:
            Text(text)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.adTextPrimary)
                .padding(.top, 4)
        case 2:
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.adTextPrimary)
                .padding(.top, 3)
        case 3:
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.adOrange)
                .padding(.top, 2)
        default:
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.adTextSecondary)
        }
    }

    @ViewBuilder
    private func inlineFormattedText(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.system(size: 13))
                .foregroundStyle(Color.adTextPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(verbatim: text)
                .font(.system(size: 13))
                .foregroundStyle(Color.adTextPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

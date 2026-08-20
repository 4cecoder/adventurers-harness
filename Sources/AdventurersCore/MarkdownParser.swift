// MarkdownParser.swift
// AdventurersCore — Pure Swift 6 Markdown Block & Structure Parser
// Tokenizes markdown into headers, lists, tasks, blockquotes, tables, dividers, code blocks, and paragraphs.

import Foundation

// MARK: - Markdown Element Model

public enum MarkdownElement: Identifiable, Sendable, Equatable {
    case header(level: Int, text: String, id: String)
    case paragraph(text: String, id: String)
    case bulletList(items: [String], id: String)
    case numberedList(items: [(number: Int, text: String)], id: String)
    case taskList(items: [(isDone: Bool, text: String)], id: String)
    case blockquote(text: String, id: String)
    case table(headers: [String], rows: [[String]], id: String)
    case divider(id: String)
    case codeBlock(language: String, code: String, id: String)

    public var id: String {
        switch self {
        case .header(_, _, let id): return id
        case .paragraph(_, let id): return id
        case .bulletList(_, let id): return id
        case .numberedList(_, let id): return id
        case .taskList(_, let id): return id
        case .blockquote(_, let id): return id
        case .table(_, _, let id): return id
        case .divider(let id): return id
        case .codeBlock(_, _, let id): return id
        }
    }

    public static func == (lhs: MarkdownElement, rhs: MarkdownElement) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Markdown Parser

public struct MarkdownParser: Sendable {
    public static func parse(markdown: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let rawLines = markdown.components(separatedBy: .newlines)
        var i = 0
        var elementCount = 0

        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. Code Block detection
            if trimmed.hasPrefix("```") {
                let rawLang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                let lang = rawLang.components(separatedBy: .whitespaces).first ?? "code"
                var codeLines: [String] = []
                i += 1
                while i < rawLines.count {
                    let codeLine = rawLines[i]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(codeLine)
                    i += 1
                }
                elementCount += 1
                elements.append(.codeBlock(
                    language: lang.isEmpty ? "code" : lang,
                    code: codeLines.joined(separator: "\n"),
                    id: "code-\(elementCount)"
                ))
                continue
            }

            // 2. Empty line skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 3. Horizontal Rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                elementCount += 1
                elements.append(.divider(id: "div-\(elementCount)"))
                i += 1
                continue
            }

            // 4. Headers (#, ##, ###, ####)
            if trimmed.hasPrefix("#") {
                var level = 0
                for ch in trimmed {
                    if ch == "#" { level += 1 } else { break }
                }
                if level <= 4 && trimmed.count > level && trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == " " {
                    let headerText = trimmed.dropFirst(level + 1).trimmingCharacters(in: .whitespaces)
                    elementCount += 1
                    elements.append(.header(level: level, text: headerText, id: "hdr-\(elementCount)"))
                    i += 1
                    continue
                }
            }

            // 5. Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < rawLines.count {
                    let qLine = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if qLine.hasPrefix(">") {
                        quoteLines.append(qLine.dropFirst().trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else if qLine.isEmpty {
                        break
                    } else {
                        break
                    }
                }
                elementCount += 1
                elements.append(.blockquote(text: quoteLines.joined(separator: "\n"), id: "quote-\(elementCount)"))
                continue
            }

            // 6. Task List (- [ ] or - [x])
            if isTaskListLine(trimmed) {
                var taskItems: [(isDone: Bool, text: String)] = []
                while i < rawLines.count {
                    let tLine = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if let task = parseTaskLine(tLine) {
                        taskItems.append(task)
                        i += 1
                    } else {
                        break
                    }
                }
                elementCount += 1
                elements.append(.taskList(items: taskItems, id: "task-\(elementCount)"))
                continue
            }

            // 7. Bullet List (- item or * item)
            if isBulletListLine(trimmed) {
                var items: [String] = []
                while i < rawLines.count {
                    let bLine = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if isBulletListLine(bLine) {
                        let itemText = bLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        items.append(itemText)
                        i += 1
                    } else {
                        break
                    }
                }
                elementCount += 1
                elements.append(.bulletList(items: items, id: "bullet-\(elementCount)"))
                continue
            }

            // 8. Numbered List (1. item)
            if isNumberedListLine(trimmed) {
                var items: [(number: Int, text: String)] = []
                while i < rawLines.count {
                    let nLine = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if let (num, txt) = parseNumberedLine(nLine) {
                        items.append((num, txt))
                        i += 1
                    } else {
                        break
                    }
                }
                elementCount += 1
                elements.append(.numberedList(items: items, id: "num-\(elementCount)"))
                continue
            }

            // 9. Markdown Table (| H1 | H2 |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && i + 1 < rawLines.count && rawLines[i + 1].contains("---") {
                let headers = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                i += 2 // skip header and divider line
                var rows: [[String]] = []
                while i < rawLines.count {
                    let rLine = rawLines[i].trimmingCharacters(in: .whitespaces)
                    if rLine.hasPrefix("|") && rLine.hasSuffix("|") {
                        let cells = rLine.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                        rows.append(cells)
                        i += 1
                    } else {
                        break
                    }
                }
                elementCount += 1
                elements.append(.table(headers: headers, rows: rows, id: "tbl-\(elementCount)"))
                continue
            }

            // 10. Default Paragraph
            var paraLines: [String] = []
            while i < rawLines.count {
                let pLine = rawLines[i]
                let pTrimmed = pLine.trimmingCharacters(in: .whitespaces)
                if pTrimmed.isEmpty || pTrimmed.hasPrefix("#") || pTrimmed.hasPrefix("```") || pTrimmed.hasPrefix(">") || isBulletListLine(pTrimmed) || isNumberedListLine(pTrimmed) || isTaskListLine(pTrimmed) || pTrimmed == "---" {
                    break
                }
                paraLines.append(pLine)
                i += 1
            }
            if !paraLines.isEmpty {
                elementCount += 1
                elements.append(.paragraph(text: paraLines.joined(separator: "\n"), id: "para-\(elementCount)"))
            }
        }

        return elements.isEmpty ? [.paragraph(text: markdown, id: "para-0")] : elements
    }

    private static func isBulletListLine(_ text: String) -> Bool {
        return (text.hasPrefix("- ") || text.hasPrefix("* ") || text.hasPrefix("+ ")) && !isTaskListLine(text)
    }

    private static func isTaskListLine(_ text: String) -> Bool {
        return text.hasPrefix("- [ ]") || text.hasPrefix("- [x]") || text.hasPrefix("- [X]")
    }

    private static func parseTaskLine(_ text: String) -> (isDone: Bool, text: String)? {
        if text.hasPrefix("- [ ]") {
            return (false, text.dropFirst(5).trimmingCharacters(in: .whitespaces))
        } else if text.hasPrefix("- [x]") || text.hasPrefix("- [X]") {
            return (true, text.dropFirst(5).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func isNumberedListLine(_ text: String) -> Bool {
        guard let dotIndex = text.firstIndex(of: ".") else { return false }
        let prefix = text[..<dotIndex]
        guard Int(prefix) != nil else { return false }
        let afterDot = text[text.index(after: dotIndex)...]
        return afterDot.hasPrefix(" ")
    }

    private static func parseNumberedLine(_ text: String) -> (number: Int, text: String)? {
        guard let dotIndex = text.firstIndex(of: ".") else { return nil }
        guard let num = Int(text[..<dotIndex]) else { return nil }
        let txt = text[text.index(after: dotIndex)...].trimmingCharacters(in: .whitespaces)
        return (num, txt)
    }
}

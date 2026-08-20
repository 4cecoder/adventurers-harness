// MarkdownParserTests.swift
// AdventurersCoreTests — Unit Tests for Native Markdown Structure & Block Parser

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Markdown Parser & High-Fidelity Structure Suite")
struct MarkdownParserTests {

    @Test("Parser extracts headers of various levels accurately")
    func parseHeaders() {
        let input = """
        # Main Title
        Some paragraph text.
        ## Subheading 2
        ### Section 3
        """
        let elements = MarkdownParser.parse(markdown: input)
        #expect(elements.count >= 4)
        if case .header(let level, let text, _) = elements[0] {
            #expect(level == 1)
            #expect(text == "Main Title")
        } else {
            Issue.record("Expected H1 header")
        }
    }

    @Test("Parser tokenizes bullet lists and numbered lists")
    func parseLists() {
        let input = """
        Here are the steps:
        - Step 1: Install Swift 6
        - Step 2: Build target
        * Step 3: Run harness

        And numbers:
        1. First item
        2. Second item
        """
        let elements = MarkdownParser.parse(markdown: input)
        let bullet = elements.first {
            if case .bulletList = $0 { return true }
            return false
        }
        let numbered = elements.first {
            if case .numberedList = $0 { return true }
            return false
        }

        #expect(bullet != nil)
        #expect(numbered != nil)

        if case .bulletList(let items, _) = bullet! {
            #expect(items.count == 3)
            #expect(items[0].contains("Step 1: Install Swift 6"))
        }

        if case .numberedList(let items, _) = numbered! {
            #expect(items.count == 2)
            #expect(items[0].number == 1)
            #expect(items[0].text == "First item")
        }
    }

    @Test("Parser extracts task lists with done and pending checkboxes")
    func parseTaskLists() {
        let input = """
        - [x] Configure cloud subscriptions
        - [ ] Verify test suite passes
        - [X] Review markdown formatting
        """
        let elements = MarkdownParser.parse(markdown: input)
        #expect(elements.count == 1)
        if case .taskList(let items, _) = elements[0] {
            #expect(items.count == 3)
            #expect(items[0].isDone == true)
            #expect(items[1].isDone == false)
            #expect(items[2].isDone == true)
        } else {
            Issue.record("Expected taskList element")
        }
    }

    @Test("Parser extracts blockquotes and tables")
    func parseQuotesAndTables() {
        let input = """
        > This is an architectural quote.
        > Multi-line support.

        | Provider | Tier | Model |
        |---|---|---|
        | OpenCode | Pro | mimo-v2.5 |
        | Hermes | Cloud | hermes-3-405b |
        """
        let elements = MarkdownParser.parse(markdown: input)
        let quote = elements.first {
            if case .blockquote = $0 { return true }
            return false
        }
        let table = elements.first {
            if case .table = $0 { return true }
            return false
        }

        #expect(quote != nil)
        #expect(table != nil)

        if case .table(let headers, let rows, _) = table! {
            #expect(headers.count == 3)
            #expect(rows.count == 2)
            #expect(rows[0][0] == "OpenCode")
            #expect(rows[1][0] == "Hermes")
        }
    }
}

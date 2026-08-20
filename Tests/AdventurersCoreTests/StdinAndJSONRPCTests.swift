// StdinAndJSONRPCTests.swift
// AdventurersCoreTests — Unit tests for TerminalStdinController and JSONRPCTransport

import Testing
import Foundation
@testable import AdventurersCore

@Suite("Interactive Stdin & JSON-RPC 2.0 LSP Transport Suite")
struct StdinAndJSONRPCTests {

    @Test("Terminal Key byte encoding produces valid VT100 control sequences")
    func testTerminalKeyEncoding() {
        #expect(TerminalKey.enter.bytes == [0x0D])
        #expect(TerminalKey.tab.bytes == [0x09])
        #expect(TerminalKey.backspace.bytes == [0x7F])
        #expect(TerminalKey.arrowUp.bytes == [0x1B, 0x5B, 0x41])
        #expect(TerminalKey.arrowDown.bytes == [0x1B, 0x5B, 0x42])
        #expect(TerminalKey.arrowRight.bytes == [0x1B, 0x5B, 0x43])
        #expect(TerminalKey.arrowLeft.bytes == [0x1B, 0x5B, 0x44])

        // Control characters
        #expect(TerminalKey.ctrl("c").bytes == [0x03]) // SIGINT
        #expect(TerminalKey.ctrl("d").bytes == [0x04]) // EOF
        #expect(TerminalKey.ctrl("z").bytes == [0x1A]) // SIGTSTP
    }

    @Test("Terminal Stdin Controller maintains navigation history")
    func testStdinHistoryNavigation() {
        let controller = TerminalStdinController()
        controller.sendLine("ls -la")
        controller.sendLine("git status")
        controller.sendLine("swift test")

        #expect(controller.historyPrevious() == "swift test")
        #expect(controller.historyPrevious() == "git status")
        #expect(controller.historyPrevious() == "ls -la")
        #expect(controller.historyNext() == "git status")
        #expect(controller.historyNext() == "swift test")
    }

    @Test("JSON-RPC Framer encodes and decodes Content-Length header frames")
    func testJSONRPCFramer() throws {
        let rawJSON = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1234}}
        """
        let payload = rawJSON.data(using: .utf8)!
        let framed = JSONRPCFramer.frame(payload: payload)

        let framedString = String(data: framed, encoding: .utf8)!
        #expect(framedString.hasPrefix("Content-Length: \(payload.count)\r\n\r\n"))

        // Decode framed stream
        let framer = JSONRPCFramer()
        let extracted = framer.append(data: framed)
        #expect(extracted.count == 1)
        #expect(extracted.first == payload)
    }

    @Test("JSON-RPC Framer handles chunked incoming buffers across packet boundaries")
    func testChunkedJSONRPCFrames() throws {
        let msg1 = """
        {"jsonrpc":"2.0","id":1,"result":"ok"}
        """
        let msg2 = """
        {"jsonrpc":"2.0","method":"window/logMessage","params":{"type":3,"message":"ready"}}
        """

        let frame1 = JSONRPCFramer.frame(payload: msg1.data(using: .utf8)!)
        let frame2 = JSONRPCFramer.frame(payload: msg2.data(using: .utf8)!)
        var combined = frame1
        combined.append(frame2)

        let framer = JSONRPCFramer()

        // Feed in 10-byte fragments
        var received: [Data] = []
        let chunkSize = 10
        var offset = 0
        while offset < combined.count {
            let end = min(offset + chunkSize, combined.count)
            let chunk = combined.subdata(in: offset..<end)
            let msgs = framer.append(data: chunk)
            received.append(contentsOf: msgs)
            offset = end
        }

        #expect(received.count == 2)
        #expect(String(data: received[0], encoding: .utf8) == msg1)
        #expect(String(data: received[1], encoding: .utf8) == msg2)
    }

    @Test("JSON-RPC Request, Response and Error serialization")
    func testJSONRPCSerialization() throws {
        struct InitParams: Codable, Sendable {
            let rootUri: String
        }

        let req = JSONRPCRequest(id: .int(42), method: "textDocument/didOpen", params: InitParams(rootUri: "file:///workspace"))
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(JSONRPCRequest<InitParams>.self, from: data)
        #expect(decoded.id == .int(42))
        #expect(decoded.method == "textDocument/didOpen")
        #expect(decoded.params?.rootUri == "file:///workspace")

        // Error serialization
        let errResp = JSONRPCResponse<String>(id: .string("req-1"), result: nil, error: .methodNotFound)
        let errData = try encoder.encode(errResp)
        let decodedErr = try decoder.decode(JSONRPCResponse<String>.self, from: errData)
        #expect(decodedErr.error?.code == -32601)
        #expect(decodedErr.error?.message == "Method not found")
    }
}

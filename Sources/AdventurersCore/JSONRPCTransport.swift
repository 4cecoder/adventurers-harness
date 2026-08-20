// JSONRPCTransport.swift
// AdventurersCore — JSON-RPC 2.0 Asynchronous Framed Transport for Language Server Protocol (LSP)
// Implements Header-based framing (`Content-Length: <N>\r\n\r\n{...}`) and bi-directional message routing.

import Foundation

// MARK: - JSON-RPC 2.0 Models

public enum JSONRPCID: Sendable, Codable, Equatable, Hashable {
    case string(String)
    case int(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let val = try? container.decode(Int.self) {
            self = .int(val)
        } else if let val = try? container.decode(String.self) {
            self = .string(val)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected string or integer ID")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s):
            try container.encode(s)
        case .int(let i):
            try container.encode(i)
        }
    }
}

public struct JSONRPCRequest<T: Codable & Sendable>: Sendable, Codable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let method: String
    public let params: T?

    public init(id: JSONRPCID, method: String, params: T? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCNotification<T: Codable & Sendable>: Sendable, Codable {
    public let jsonrpc: String
    public let method: String
    public let params: T?

    public init(method: String, params: T? = nil) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Sendable, Codable, Error, Equatable {
    public let code: Int
    public let message: String
    public let data: String?

    public init(code: Int, message: String, data: String? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard LSP Error Codes
    public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static let internalError = JSONRPCError(code: -32603, message: "Internal error")
    public static let serverNotInitialized = JSONRPCError(code: -32002, message: "Server not initialized")
    public static let requestCancelled = JSONRPCError(code: -32800, message: "Request cancelled")
}

public struct JSONRPCResponse<T: Codable & Sendable>: Sendable, Codable {
    public let jsonrpc: String
    public let id: JSONRPCID
    public let result: T?
    public let error: JSONRPCError?

    public init(id: JSONRPCID, result: T? = nil, error: JSONRPCError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }
}

// MARK: - JSON-RPC Framer & Decoder

public final class JSONRPCFramer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    public init() {}

    /// Encodes payload with standard `Content-Length: <n>\r\n\r\n` header
    public static func frame(payload: Data) -> Data {
        let header = "Content-Length: \(payload.count)\r\n\r\n"
        var data = header.data(using: .utf8) ?? Data()
        data.append(payload)
        return data
    }

    /// Feeds incoming data chunk and extracts complete framed payloads
    public func append(data: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        var messages: [Data] = []

        while true {
            guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                break
            }

            let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
            guard let headerStr = String(data: headerData, encoding: .utf8) else {
                // Invalid header, discard up to delimiter
                buffer.removeSubrange(0..<headerEndRange.upperBound)
                continue
            }

            // Parse Content-Length
            var contentLength: Int?
            for line in headerStr.components(separatedBy: "\r\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 && parts[0].lowercased() == "content-length" {
                    contentLength = Int(parts[1])
                }
            }

            guard let length = contentLength else {
                buffer.removeSubrange(0..<headerEndRange.upperBound)
                continue
            }

            let messageStart = headerEndRange.upperBound
            let messageEnd = messageStart + length

            if buffer.count >= messageEnd {
                let messageData = buffer.subdata(in: messageStart..<messageEnd)
                messages.append(messageData)
                buffer.removeSubrange(0..<messageEnd)
            } else {
                // Not enough bytes arrived yet for this frame
                break
            }
        }

        return messages
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}

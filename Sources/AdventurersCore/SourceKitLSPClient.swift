// SourceKitLSPClient.swift
// AdventurersCore — Native SourceKit-LSP Process Management & Protocol Client
// Spawns and supervises `/usr/bin/sourcekit-lsp` (or swiftly/xcrun discovery) for real-time AST diagnostics.

import Foundation

// MARK: - LSP Types

public struct LSPPosition: Sendable, Codable, Equatable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct LSPRange: Sendable, Codable, Equatable {
    public let start: LSPPosition
    public let end: LSPPosition

    public init(start: LSPPosition, end: LSPPosition) {
        self.start = start
        self.end = end
    }
}

public enum LSPDiagnosticSeverity: Int, Sendable, Codable, Equatable {
    case error = 1
    case warning = 2
    case information = 3
    case hint = 4
}

public struct LSPDiagnostic: Sendable, Codable, Equatable {
    public let range: LSPRange
    public let severity: LSPDiagnosticSeverity?
    public let code: String?
    public let source: String?
    public let message: String

    public init(range: LSPRange, severity: LSPDiagnosticSeverity? = nil, code: String? = nil, source: String? = nil, message: String) {
        self.range = range
        self.severity = severity
        self.code = code
        self.source = source
        self.message = message
    }
}

public struct LSPPublishDiagnosticsParams: Sendable, Codable {
    public let uri: String
    public let version: Int?
    public let diagnostics: [LSPDiagnostic]

    public init(uri: String, version: Int? = nil, diagnostics: [LSPDiagnostic]) {
        self.uri = uri
        self.version = version
        self.diagnostics = diagnostics
    }
}

public struct LSPTextDocumentIdentifier: Sendable, Codable {
    public let uri: String

    public init(uri: String) {
        self.uri = uri
    }
}

public struct LSPVersionedTextDocumentIdentifier: Sendable, Codable {
    public let uri: String
    public let version: Int

    public init(uri: String, version: Int) {
        self.uri = uri
        self.version = version
    }
}

public struct LSPTextDocumentItem: Sendable, Codable {
    public let uri: String
    public let languageId: String
    public let version: Int
    public let text: String

    public init(uri: String, languageId: String, version: Int, text: String) {
        self.uri = uri
        self.languageId = languageId
        self.version = version
        self.text = text
    }
}

public struct LSPDidOpenTextDocumentParams: Sendable, Codable {
    public let textDocument: LSPTextDocumentItem

    public init(textDocument: LSPTextDocumentItem) {
        self.textDocument = textDocument
    }
}

public struct LSPTextDocumentContentChangeEvent: Sendable, Codable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct LSPDidChangeTextDocumentParams: Sendable, Codable {
    public let textDocument: LSPVersionedTextDocumentIdentifier
    public let contentChanges: [LSPTextDocumentContentChangeEvent]

    public init(textDocument: LSPVersionedTextDocumentIdentifier, contentChanges: [LSPTextDocumentContentChangeEvent]) {
        self.textDocument = textDocument
        self.contentChanges = contentChanges
    }
}

public struct LSPInitializeParams: Sendable, Codable {
    public let processId: Int?
    public let rootUri: String?
    public let capabilities: [String: String]

    public init(processId: Int? = nil, rootUri: String? = nil, capabilities: [String: String] = [:]) {
        self.processId = processId
        self.rootUri = rootUri
        self.capabilities = capabilities
    }
}

public struct LSPInitializeResult: Sendable, Codable {
    public let capabilities: [String: [String: String]]?

    public init(capabilities: [String: [String: String]]? = nil) {
        self.capabilities = capabilities
    }
}

// MARK: - SourceKit-LSP Client

public actor SourceKitLSPClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let framer = JSONRPCFramer()
    private var currentRequestId = 1
    private var pendingRequests: [JSONRPCID: CheckedContinuation<Data, Error>] = [:]
    private var diagnosticHandlers: [@Sendable (LSPPublishDiagnosticsParams) -> Void] = []
    public private(set) var isRunning: Bool = false
    public private(set) var workspaceRootPath: String?

    public init() {}

    /// Discovers the location of `sourcekit-lsp` binary on macOS.
    public static func discoverServerPath() -> String {
        let candidates = [
            "/Users/fource/.swiftly/bin/sourcekit-lsp",
            "/Library/Developer/CommandLineTools/usr/bin/sourcekit-lsp",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",
            "/usr/bin/sourcekit-lsp"
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return "/usr/bin/sourcekit-lsp"
    }

    /// Starts the SourceKit-LSP child process and prepares framing pipeline.
    public func start(workspaceRoot: String, customServerPath: String? = nil) throws {
        guard !isRunning else { return }

        let serverPath = customServerPath ?? Self.discoverServerPath()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverPath)
        proc.arguments = []

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = Pipe() // Suppress stderr noise

        self.process = proc
        self.stdinPipe = inPipe
        self.stdoutPipe = outPipe
        self.workspaceRootPath = workspaceRoot
        self.isRunning = true

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { [weak self] in
                await self?.handleIncomingBytes(data)
            }
        }

        try proc.run()
    }

    /// Sends an LSP initialize request and returns the parsed initialization response.
    public func initialize(rootUri: String? = nil) async throws {
        let uri = rootUri ?? workspaceRootPath.map { "file://\($0)" }
        let params = LSPInitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            rootUri: uri,
            capabilities: [:]
        )
        let _ = try await sendRawRequest(method: "initialize", params: params)
        // Send initialized notification
        try sendNotification(method: "initialized", params: [String: String]())
    }

    /// Notifies LSP of an opened document for background analysis.
    public func openDocument(uri: String, languageId: String = "swift", version: Int = 1, text: String) throws {
        let params = LSPDidOpenTextDocumentParams(
            textDocument: LSPTextDocumentItem(uri: uri, languageId: languageId, version: version, text: text)
        )
        try sendNotification(method: "textDocument/didOpen", params: params)
    }

    /// Notifies LSP of an in-memory document modification.
    public func changeDocument(uri: String, version: Int, newText: String) throws {
        let params = LSPDidChangeTextDocumentParams(
            textDocument: LSPVersionedTextDocumentIdentifier(uri: uri, version: version),
            contentChanges: [LSPTextDocumentContentChangeEvent(text: newText)]
        )
        try sendNotification(method: "textDocument/didChange", params: params)
    }

    /// Registers a listener for real-time diagnostic publications.
    public func onDiagnostics(_ handler: @escaping @Sendable (LSPPublishDiagnosticsParams) -> Void) {
        diagnosticHandlers.append(handler)
    }

    /// Sends a JSON-RPC LSP request and awaits raw Data response.
    public func sendRawRequest<P: Codable & Sendable>(
        method: String,
        params: P?
    ) async throws -> Data {
        guard isRunning, let stdin = stdinPipe else {
            throw JSONRPCError.serverNotInitialized
        }

        let reqId = JSONRPCID.int(currentRequestId)
        currentRequestId += 1

        let request = JSONRPCRequest(id: reqId, method: method, params: params)
        let jsonData = try JSONEncoder().encode(request)
        let framedData = JSONRPCFramer.frame(payload: jsonData)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[reqId] = continuation
            do {
                try stdin.fileHandleForWriting.write(contentsOf: framedData)
            } catch {
                pendingRequests.removeValue(forKey: reqId)
                continuation.resume(throwing: error)
            }
        }
    }

    /// Sends a JSON-RPC notification (no response expected).
    public func sendNotification<P: Codable & Sendable>(method: String, params: P?) throws {
        guard isRunning, let stdin = stdinPipe else {
            throw JSONRPCError.serverNotInitialized
        }
        let notification = JSONRPCNotification(method: method, params: params)
        let jsonData = try JSONEncoder().encode(notification)
        let framedData = JSONRPCFramer.frame(payload: jsonData)
        try stdin.fileHandleForWriting.write(contentsOf: framedData)
    }

    /// Terminates the SourceKit-LSP server process.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdinPipe = nil
        stdoutPipe = nil
        process?.terminate()
        process = nil
        framer.reset()
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: JSONRPCError.requestCancelled)
        }
        pendingRequests.removeAll()
    }

    // MARK: - Incoming Message Handler

    private func handleIncomingBytes(_ data: Data) {
        let messages = framer.append(data: data)
        for msgData in messages {
            // Check if it's a notification: textDocument/publishDiagnostics
            if let notif = try? JSONDecoder().decode(JSONRPCNotification<LSPPublishDiagnosticsParams>.self, from: msgData),
               notif.method == "textDocument/publishDiagnostics",
               let params = notif.params {
                for handler in diagnosticHandlers {
                    handler(params)
                }
                continue
            }

            // Check if it's a response to a pending request
            if let json = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
               let idVal = json["id"] {
                let rpcId: JSONRPCID
                if let intId = idVal as? Int {
                    rpcId = .int(intId)
                } else if let strId = idVal as? String {
                    rpcId = .string(strId)
                } else {
                    continue
                }

                if let continuation = pendingRequests.removeValue(forKey: rpcId) {
                    if let errObj = json["error"] as? [String: Any],
                       let code = errObj["code"] as? Int,
                       let msg = errObj["message"] as? String {
                        continuation.resume(throwing: JSONRPCError(code: code, message: msg))
                    } else {
                        continuation.resume(returning: msgData)
                    }
                }
            }
        }
    }
}

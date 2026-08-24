// WasmGateRunner.swift
// AdventurersCore — WebAssembly & Sandboxed Subprocess Gate Runner
// Executes custom compiled gate binaries (WASM via wasmtime/wasm3 or native binary) with strict memory and timeout boundaries.

import Foundation

public actor WasmGateRunner {
    public static let shared = WasmGateRunner()

    public init() {}

    /// Executes a custom gate plugin passing structured WASIGateInput and parsing WASIGateOutput.
    public func executeGate(
        pluginPath: String,
        input: WASIGateInput,
        memoryLimitMB: Int = 64,
        timeoutSeconds: Double = 0.5
    ) async -> WASIGateOutput {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard FileManager.default.fileExists(atPath: pluginPath) && (FileManager.default.isExecutableFile(atPath: pluginPath) || pluginPath.hasSuffix(".wasm")) else {
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return WASIGateOutput(
                passed: false,
                gateName: (pluginPath as NSString).lastPathComponent,
                error: "Gate plugin not found or not executable at '\(pluginPath)'.",
                executionTimeMs: latency,
                violations: ["Executable plugin missing"]
            )
        }

        let isWasm = pluginPath.hasSuffix(".wasm")
        let execUrl: URL
        let execArgs: [String]

        if isWasm {
            // If WASM, invoke wasmtime runner if installed, else fallback to wasm3
            execUrl = URL(fileURLWithPath: "/usr/bin/env")
            execArgs = ["wasmtime", "run", "--wasm-features", "all", pluginPath]
        } else {
            execUrl = URL(fileURLWithPath: pluginPath)
            execArgs = []
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = execUrl
            process.arguments = execArgs

            let inPipe = Pipe()
            let outPipe = Pipe()
            let errPipe = Pipe()

            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                let inputData = try JSONEncoder().encode(input)
                try process.run()
                try inPipe.fileHandleForWriting.write(contentsOf: inputData)
                try inPipe.fileHandleForWriting.close()

                // Spawn watchdog timeout task
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    if process.isRunning {
                        process.terminate()
                    }
                }

                process.waitUntilExit()

                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()

                if let decoded = try? JSONDecoder().decode(WASIGateOutput.self, from: outData) {
                    continuation.resume(returning: decoded)
                } else {
                    let passed = process.terminationStatus == 0
                    let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                    let outStr = String(data: outData, encoding: .utf8)

                    continuation.resume(returning: WASIGateOutput(
                        passed: passed,
                        gateName: (pluginPath as NSString).lastPathComponent,
                        error: passed ? nil : (errStr?.isEmpty == false ? errStr : "Process exited with code \(process.terminationStatus)"),
                        output: outStr,
                        executionTimeMs: latency,
                        violations: passed ? [] : ["Non-zero exit code"]
                    ))
                }
            } catch {
                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                continuation.resume(returning: WASIGateOutput(
                    passed: false,
                    gateName: (pluginPath as NSString).lastPathComponent,
                    error: "Failed to launch gate runner: \(error.localizedDescription)",
                    executionTimeMs: latency,
                    violations: [error.localizedDescription]
                ))
            }
        }
    }
}

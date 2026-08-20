// HindsightDockerGate.swift
// AdventurersCore — Local Docker Memory Gate
//
// Ensures Hindsight memory is strictly excluded from the execution loop unless
// actively running in a local Docker container on localhost.
// Otherwise, falls back to native on-device OKF Knowledge Packets with zero latency.
//
// Pure Swift 6 · Sendable-safe

import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct HindsightDockerGate: Sendable {
    public let dockerPort: Int
    public let timeoutSeconds: Double

    public init(dockerPort: Int = 8888, timeoutSeconds: Double = 0.15) {
        self.dockerPort = dockerPort
        self.timeoutSeconds = timeoutSeconds
    }

    /// Fast non-blocking socket check to verify if Hindsight is running in local Docker
    public func isDockerHindsightAvailable() -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(dockerPort).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Set non-blocking timeout
        var tv = timeval(tv_sec: 0, tv_usec: suseconds_t(timeoutSeconds * 1_000_000))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }
}

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "adventurers-harness",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Adventurers", targets: ["GUI"]),
        .executable(name: "adventurers", targets: ["CLI"]),
        .executable(name: "adventurers-mcp", targets: ["UnifiedMemoryMCPServer"]),
        .library(name: "AdventurersCore", targets: ["AdventurersCore"]),
        .library(name: "LLMProviders", targets: ["LLMProviders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
    ],
    targets: [
        // Core harness: agent loop, FSM, gates, contracts, journal
        .target(
            name: "AdventurersCore",
            dependencies: [
                "LLMProviders",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // LLM provider abstraction
        .target(
            name: "LLMProviders",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Built-in tools: file, bash, grep, glob
        .target(
            name: "Tools",
            dependencies: [
                "AdventurersCore",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Native macOS SwiftUI GUI application
        .executableTarget(
            name: "GUI",
            dependencies: [
                "AdventurersCore",
                "LLMProviders",
                "Tools",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/GUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Headless CLI Tool & Task Runner
        .executableTarget(
            name: "CLI",
            dependencies: [
                "AdventurersCore",
                "LLMProviders",
                "Tools",
            ],
            path: "Sources/CLI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Unified Native Swift MCP Server for All Coding Agent CLIs (AGY, Claude Code, Cursor, OpenCode, Codex)
        .executableTarget(
            name: "UnifiedMemoryMCPServer",
            dependencies: [
                "AdventurersCore",
            ],
            path: "Sources/UnifiedMemoryMCPServer",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Tests
        .testTarget(
            name: "AdventurersCoreTests",
            dependencies: ["AdventurersCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)

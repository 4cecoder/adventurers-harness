// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "adventurers-harness",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Adventurers", targets: ["GUI"]),
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

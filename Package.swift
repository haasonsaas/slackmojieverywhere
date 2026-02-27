// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SlackmojiEverywhere",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SlackmojiEverywhere",
            targets: ["SlackmojiEverywhere"]
        )
    ],
    targets: [
        .target(
            name: "SlackmojiCore",
            path: "Sources/SlackmojiCore"
        ),
        .executableTarget(
            name: "SlackmojiEverywhere",
            dependencies: [
                "SlackmojiCore"
            ],
            path: "Sources",
            exclude: [
                "SlackmojiCore"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "SlackmojiCoreTests",
            dependencies: [
                "SlackmojiCore"
            ],
            path: "Tests/SlackmojiCoreTests"
        )
    ]
)

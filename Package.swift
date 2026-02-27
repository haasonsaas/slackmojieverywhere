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
        .executableTarget(
            name: "SlackmojiEverywhere",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

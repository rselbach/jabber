// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Jabber",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Jabber", targets: ["Jabber"])
    ],
    dependencies: [
        .package(url: "https://github.com/ejbills/mediaremote-adapter", revision: "78aae86c03adab11a7b352211cc82381737cf854"),
        .package(url: "https://github.com/soniqo/speech-swift", revision: "373f0101c9e9fe9b540362c0b45a2c618ce84a6c"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0")
    ],
    targets: [
        .executableTarget(
            name: "Jabber",
            dependencies: [
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
                .product(name: "Qwen3ASR", package: "speech-swift"),
                .product(name: "NemotronStreamingASR", package: "speech-swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Jabber",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "JabberTests",
            dependencies: ["Jabber"],
            path: "Tests/JabberTests"
        )
    ]
)

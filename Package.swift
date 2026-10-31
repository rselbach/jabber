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
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.0", traits: []),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0")
    ],
    targets: [
        .executableTarget(
            name: "Jabber",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MediaRemoteAdapter", package: "mediaremote-adapter"),
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

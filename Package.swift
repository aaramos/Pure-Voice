// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PureVoice",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PureVoiceCore", targets: ["PureVoiceCore"]),
        .executable(name: "PureVoice", targets: ["PureVoiceApp"])
    ],
    targets: [
        .target(
            name: "PureVoiceCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "PureVoiceApp",
            dependencies: ["PureVoiceCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "PureVoiceCoreTests",
            dependencies: ["PureVoiceCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)

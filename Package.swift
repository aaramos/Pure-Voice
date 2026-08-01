// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PureVoice",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "PureVoiceCore", targets: ["PureVoiceCore"]),
        .executable(name: "PureVoice", targets: ["PureVoiceApp"])
    ],
    targets: [
        .target(
            name: "PureVoiceCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("Speech"),
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
                .linkedFramework("AVFoundation"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("Speech"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)

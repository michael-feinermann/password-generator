// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasswordGenerator",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PasswordGeneratorCore", targets: ["PasswordGeneratorCore"]),
        .executable(name: "PasswordGeneratorApp", targets: ["PasswordGeneratorApp"]),
        .executable(name: "PasswordGeneratorChecksum", targets: ["PasswordGeneratorChecksum"])
    ],
    targets: [
        .target(
            name: "PasswordGeneratorCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "PasswordGeneratorApp",
            dependencies: ["PasswordGeneratorCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "PasswordGeneratorChecksum",
            dependencies: ["PasswordGeneratorCore"]
        ),
        .testTarget(
            name: "PasswordGeneratorCoreTests",
            dependencies: ["PasswordGeneratorCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PasswordGeneratorAppTests",
            dependencies: ["PasswordGeneratorApp"]
        )
    ]
)

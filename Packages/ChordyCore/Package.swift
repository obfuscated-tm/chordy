// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChordyCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ChordyCore", targets: ["ChordyCore"]),
        .executable(name: "chordy", targets: ["chordy"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "ChordyCore",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
        .executableTarget(name: "chordy", dependencies: ["ChordyCore"]),
        .testTarget(
            name: "ChordyCoreTests",
            dependencies: ["ChordyCore"],
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
        ),
    ],
    swiftLanguageModes: [.v5]
)

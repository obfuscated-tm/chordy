// swift-tools-version: 6.2
import PackageDescription

// Kept apart from ChordyCore so the core builds and tests without MLX and its macro toolchain.
// MLX needs its Metal shaders, which only an Xcode build compiles: use it from the app, not `swift run`.
let package = Package(
    name: "ChordyMLX",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "ChordyMLX", targets: ["ChordyMLX"]),
    ],
    dependencies: [
        .package(path: "../ChordyCore"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ChordyMLX",
            dependencies: [
                .product(name: "ChordyCore", package: "ChordyCore"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

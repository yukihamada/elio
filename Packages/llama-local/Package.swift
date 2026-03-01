// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "llama-local",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "LlamaSwift",
            targets: ["LlamaSwift"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "llama-cpp",
            path: "../../Frameworks/llama.xcframework"
        ),
        .target(
            name: "LlamaSwift",
            dependencies: ["llama-cpp"],
            path: "Sources/LlamaSwift"
        ),
    ]
)

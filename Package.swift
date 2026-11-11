// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MCBUpload",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MCBUploadCore", targets: ["MCBUploadCore"]),
        .executable(name: "mcb", targets: ["mcb"]),
    ],
    targets: [
        .target(name: "MCBUploadCore"),
        .executableTarget(name: "mcb", dependencies: ["MCBUploadCore"]),
        .testTarget(name: "MCBUploadCoreTests", dependencies: ["MCBUploadCore"]),
    ]
)

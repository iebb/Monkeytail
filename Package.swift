// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonkeytailCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MonkeytailCore", targets: ["MonkeytailCore"])],
    targets: [
        .target(name: "MonkeytailCore"),
        .testTarget(name: "MonkeytailCoreTests", dependencies: ["MonkeytailCore"])
    ]
)

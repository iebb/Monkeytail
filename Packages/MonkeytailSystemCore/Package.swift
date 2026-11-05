// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MonkeytailSystemCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .visionOS(.v1)],
    products: [.library(name: "MonkeytailSystemCore", targets: ["MonkeytailSystemCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [.target(name: "MonkeytailSystemCore", dependencies: ["Yams"], resources: [.process("Resources")])]
)

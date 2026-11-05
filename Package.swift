// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonkeytailCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MonkeytailCore", targets: ["MonkeytailCore"]), .library(name: "MonkeytailCompanion", targets: ["MonkeytailCompanion"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [
        .target(name: "MonkeytailCompanion", resources: [.process("Resources")]),
        .binaryTarget(name: "CurlImpersonate", path: "Vendor/CurlImpersonate.xcframework"),
        .target(name: "MonkeytailCurl", dependencies: ["CurlImpersonate"], linkerSettings: [
            .linkedFramework("Security"), .linkedFramework("CoreFoundation"),
            .linkedFramework("SystemConfiguration"), .linkedLibrary("c++"), .linkedLibrary("resolv"),
            .linkedLibrary("iconv"), .linkedLibrary("icucore")
        ]),
        .target(name: "MonkeytailCore", dependencies: ["MonkeytailCurl", "Yams"], resources: [.process("Resources")]),
        .testTarget(name: "MonkeytailCoreTests", dependencies: ["MonkeytailCore"], exclude: ["Fixtures"]),
        .testTarget(name: "MonkeytailCompanionTests", dependencies: ["MonkeytailCompanion"])
    ]
)

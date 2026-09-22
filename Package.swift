// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonkeytailCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MonkeytailCore", targets: ["MonkeytailCore"])],
    targets: [
        .binaryTarget(name: "CurlImpersonate", path: "Vendor/CurlImpersonate.xcframework"),
        .target(name: "MonkeytailCurl", dependencies: ["CurlImpersonate"], linkerSettings: [
            .linkedFramework("Security"), .linkedFramework("CoreFoundation"),
            .linkedFramework("SystemConfiguration"), .linkedLibrary("c++"), .linkedLibrary("resolv"),
            .linkedLibrary("iconv"), .linkedLibrary("icucore")
        ]),
        .target(name: "MonkeytailCore", dependencies: ["MonkeytailCurl"], resources: [.process("Resources")]),
        .testTarget(name: "MonkeytailCoreTests", dependencies: ["MonkeytailCore"])
    ]
)

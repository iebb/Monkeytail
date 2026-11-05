// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MonkeytailWatchCore", defaultLocalization: "en", platforms: [.watchOS(.v10)], products: [.library(name: "MonkeytailWatchCore", targets: ["MonkeytailWatchCore"])], targets: [.target(name: "MonkeytailWatchCore", resources: [.process("Resources")])])

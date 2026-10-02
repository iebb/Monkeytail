// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MonkeytailWatchCore", platforms: [.watchOS(.v10)], products: [.library(name: "MonkeytailWatchCore", targets: ["MonkeytailWatchCore"])], targets: [.target(name: "MonkeytailWatchCore")])

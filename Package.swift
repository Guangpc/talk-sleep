// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SleepMate",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SleepMateCore", targets: ["SleepMateCore"])],
    targets: [
        .target(name: "SleepMateCore"),
        .testTarget(name: "SleepMateCoreTests", dependencies: ["SleepMateCore"])
    ]
)

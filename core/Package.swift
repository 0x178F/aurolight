// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AurolightCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "AurolightCore", targets: ["AurolightCore"])],
    targets: [
        .target(name: "AurolightCore"),
        .testTarget(name: "AurolightCoreTests", dependencies: ["AurolightCore"]),
    ]
)

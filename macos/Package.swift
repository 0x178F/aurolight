// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Aurolight",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../core")],
    targets: [
        .executableTarget(name: "Aurolight", dependencies: [.product(name: "AurolightCore", package: "core")]),
        .testTarget(name: "AurolightTests", dependencies: ["Aurolight"]),
    ]
)

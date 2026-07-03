// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SphereView360",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SphereView360", targets: ["SphereView360"])
    ],
    targets: [
        .executableTarget(name: "SphereView360")
    ]
)


// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Geet",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Geet", targets: ["Geet"]), .library(name: "GeetCore", targets: ["GeetCore"])],
    targets: [
        .target(name: "GeetCore", resources: [.process("Resources")]),
        .executableTarget(name: "Geet", dependencies: ["GeetCore"], resources: [.process("Resources")]),
        .testTarget(name: "GeetCoreTests", dependencies: ["GeetCore"]),
        .testTarget(name: "GeetTests", dependencies: ["Geet", "GeetCore"])
    ],
    swiftLanguageModes: [.v5]
)

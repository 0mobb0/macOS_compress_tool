// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CleanZip", platforms: [.macOS(.v13)],
    products: [.executable(name: "CleanZip", targets: ["CleanZip"]), .executable(name: "zipcheck", targets: ["zipcheck"])],
    targets: [
        .target(name: "CZip", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "ZipCore", dependencies: ["CZip"]),
        .executableTarget(name: "CleanZip", dependencies: ["ZipCore"]),
        .executableTarget(name: "zipcheck", dependencies: ["ZipCore"]),
        .testTarget(name: "ZipCoreTests", dependencies: ["ZipCore"])
    ])

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Instant",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Instant", targets: ["Instant"])],
    targets: [
        .target(name: "InstantCore"),
        .target(name: "MaterialViewPrivate", path: "Vendor/MaterialView/Sources/MaterialViewPrivate", publicHeadersPath: "include"),
        .target(name: "MaterialView", dependencies: ["MaterialViewPrivate"], path: "Vendor/MaterialView/Sources/MaterialView"),
        .executableTarget(name: "Instant", dependencies: ["InstantCore", "MaterialView"]),
        .testTarget(name: "InstantCoreTests", dependencies: ["InstantCore"]),
        .testTarget(name: "InstantScrollTests", dependencies: ["Instant", "InstantCore"])
    ],
    swiftLanguageModes: [.v5]
)

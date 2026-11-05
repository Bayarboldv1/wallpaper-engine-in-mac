// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Luma", targets: ["Luma"])],
    targets: [
        .executableTarget(name: "Luma", resources: [.copy("Resources/Scenes")]),
        .testTarget(name: "LumaTests", dependencies: ["Luma"])
    ],
    swiftLanguageModes: [.v5]
)

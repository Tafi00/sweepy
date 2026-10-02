// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sweepy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Sweepy", path: "Sources/Sweepy")
    ]
)

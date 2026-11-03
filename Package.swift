// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Quire",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Quire", path: "Sources/Quire")
    ]
)

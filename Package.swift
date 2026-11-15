// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Quire",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Quire", path: "Sources/Quire")
    ],
    swiftLanguageModes: [.v5]
)

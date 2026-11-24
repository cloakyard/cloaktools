// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloakToolsCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "CloakToolsCore", targets: ["CloakToolsCore"])],
    dependencies: [.package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.6.0")],
    targets: [
        .target(name: "CloakToolsCore", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]),
        .testTarget(name: "CloakToolsCoreTests", dependencies: ["CloakToolsCore"])
    ]
)

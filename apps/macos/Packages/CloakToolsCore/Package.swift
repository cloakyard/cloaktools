// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CloakToolsCore", platforms: [.macOS("27.0")], products: [
    .library(name: "CloakToolsCore", targets: ["CloakToolsCore"])
], targets: [.target(name: "CloakToolsCore"), .testTarget(name: "CloakToolsCoreTests", dependencies: ["CloakToolsCore"])])

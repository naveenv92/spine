// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Spine", platforms: [.macOS(.v14)], products: [.executable(name: "Spine", targets: ["Spine"])], targets: [.executableTarget(name: "Spine", resources: [.copy("Resources/AppIcon.png"), .copy("Resources/Fonts")]), .testTarget(name: "SpineTests", dependencies: ["Spine"])])

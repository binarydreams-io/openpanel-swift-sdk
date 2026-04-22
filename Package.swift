// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "OpenPanel",
  platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
  products: [
    .library(name: "OpenPanel", targets: ["OpenPanel"])
  ],
  targets: [
    .target(name: "OpenPanel"),
    .testTarget(name: "OpenPanelTests", dependencies: ["OpenPanel"])
  ]
)

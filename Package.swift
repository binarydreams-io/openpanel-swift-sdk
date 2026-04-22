// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OpenPanel",
  platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
  products: [
    .library(name: "OpenPanel", targets: ["OpenPanel"])
  ],
  targets: [
    .target(name: "OpenPanel"),
    .testTarget(name: "OpenPanelTests", dependencies: ["OpenPanel"])
  ]
)

// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "OpenPanel",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v15)
  ],
  products: [
    .library(
      name: "OpenPanel",
      targets: ["OpenPanel"]
    )
  ],
  targets: [
    .target(
      name: "OpenPanel",
      path: "Sources"
    ),
    .testTarget(
      name: "OpenPanelTests",
      dependencies: ["OpenPanel"],
      path: "Tests"
    )
  ]
)

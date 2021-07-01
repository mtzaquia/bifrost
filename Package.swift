// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Bifrost",
  platforms: [
    .iOS(.v14)
  ],
  products: [
    .library(
      name: "Bifrost",
      targets: ["Bifrost"]),
  ],
  targets: [
    .target(
      name: "Bifrost",
      dependencies: []),
    .testTarget(
      name: "BifrostTests",
      dependencies: ["Bifrost"]),
  ]
)

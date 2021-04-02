// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SwiftNoise",
  products: [
    .library(name: "SwiftNoise", targets: ["SwiftNoise"])
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .revision("5669f222e46c8134fb1f399c745fa6882b43532e")), // v1.3.8
    .package(url: "https://github.com/christophhagen/CryptoKit25519", .revision("d1feb6533039fedc36a4004bd32b328f18a7e653"))  // v0.4.2
  ],
  targets: [
    // Targets are the basic building blocks of a package. A target can define a module or a test suite.
    // Targets can depend on other targets in this package, and on products in packages which this package depends on.
    .target(
      name: "SwiftNoise",
      dependencies: [
        "CryptoSwift",
        "CryptoKit25519"
      ]),
    .testTarget(
      name: "SwiftNoiseTests",
      dependencies: [
        "SwiftNoise"
      ])
  ]
)

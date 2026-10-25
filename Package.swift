// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "UsageMonitor",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "UsageMonitor", targets: ["UsageMonitor"])],
  targets: [
    .target(name: "UsageCore"),
    .executableTarget(name: "UsageMonitor", dependencies: ["UsageCore"]),
    .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
  ]
)

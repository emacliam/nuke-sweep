// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Nuke", platforms: [.macOS(.v14)], products: [.executable(name: "Nuke", targets: ["Nuke"])], targets: [.target(name: "NukeMetrics"), .target(name: "NukeWidgetUI", dependencies: ["NukeMetrics"]), .executableTarget(name: "Nuke", dependencies: ["NukeMetrics", "NukeWidgetUI"]), .testTarget(name: "NukeTests", dependencies: ["Nuke", "NukeMetrics", "NukeWidgetUI"])], swiftLanguageModes: [.v5])

// swift-tools-version: 6.0
import PackageDescription

// Every non-test target builds in Swift 6 language mode, so data-race safety is
// enforced by the compiler rather than asserted by convention. The handful of
// places where an unannotated Objective-C callback cannot be proven safe use
// `nonisolated(unsafe)` with the runtime guarantee stated at the site, and
// `MainActor.assumeIsolated` to trap if that guarantee is ever violated.
//
// Tests stay in Swift 5 mode: XCTest's own lifecycle is not fully annotated, and
// migrating them would add noise without testing anything new.
let package = Package(
    name: "Nuke",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Nuke", targets: ["Nuke"])],
    targets: [
        .target(name: "NukeMetrics", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "NukeWidgetUI", dependencies: ["NukeMetrics"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "Nuke",
            dependencies: ["NukeMetrics", "NukeWidgetUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "NukeTests", dependencies: ["Nuke", "NukeMetrics", "NukeWidgetUI"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)

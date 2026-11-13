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
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
        ),
        .target(name: "NukeMetrics", swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "NukeWidgetUI", dependencies: ["NukeMetrics"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "Nuke",
            dependencies: ["NukeMetrics", "NukeWidgetUI", "Sparkle"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "NukeTests", dependencies: ["Nuke", "NukeMetrics", "NukeWidgetUI"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)

// swift-tools-version: 6.2
import Foundation
import PackageDescription

// The prototype pins the matching ScreenKit PR commit. Local validation can substitute
// that checkout without changing the published dependencies of either app.
let screenKit: Package.Dependency = if let path = ProcessInfo.processInfo.environment["SCREENKIT_TELEMETRY_PATH"] {
    .package(path: path)
} else {
    .package(url: "https://github.com/SoundBlaster/ScreenKit.git", revision: "8811665c7d860efc2a11c8709a21fe39232b4e07")
}

let package = Package(
    name: "ScreenKitOpenTelemetry",
    platforms: [.iOS(.v18), .macOS(.v12)],
    products: [.library(name: "ScreenKitOpenTelemetry", targets: ["ScreenKitOpenTelemetry"])],
    dependencies: [
        screenKit,
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", exact: "2.5.1")
    ],
    targets: [
        .target(name: "ScreenKitOpenTelemetry", dependencies: [
            .product(name: "ScreenKit", package: "ScreenKit"),
            .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core")
        ]),
        .testTarget(name: "ScreenKitOpenTelemetryTests", dependencies: [
            "ScreenKitOpenTelemetry",
            .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core")
        ])
    ]
)

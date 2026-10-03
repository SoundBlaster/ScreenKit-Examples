// swift-tools-version: 6.2
import Foundation
import PackageDescription

let screenKit: Package.Dependency = if let path = ProcessInfo.processInfo.environment["SCREENKIT_TELEMETRY_PATH"] {
    .package(path: path)
} else {
    .package(url: "https://github.com/SoundBlaster/ScreenKit.git", revision: "8811665c7d860efc2a11c8709a21fe39232b4e07")
}

let package = Package(
    name: "ScreenKitTelemetryMonitor",
    platforms: [.iOS(.v18), .macOS(.v12)],
    products: [
        .library(name: "ScreenKitTelemetryMonitor", targets: ["ScreenKitTelemetryMonitor"]),
        .executable(name: "ScreenKitTelemetryProducer", targets: ["ScreenKitTelemetryProducer"])
    ],
    dependencies: [
        screenKit,
        .package(path: "../ScreenKitOpenTelemetry"),
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift.git", exact: "2.5.1")
    ],
    targets: [
        .target(name: "ScreenKitTelemetryMonitor", dependencies: [
            .product(name: "ScreenKitOpenTelemetry", package: "ScreenKitOpenTelemetry"),
            .product(name: "OpenTelemetryProtocolExporterHTTP", package: "opentelemetry-swift")
        ]),
        .executableTarget(name: "ScreenKitTelemetryProducer", dependencies: [
            "ScreenKitTelemetryMonitor", .product(name: "ScreenKit", package: "ScreenKit")
        ]),
        .testTarget(name: "ScreenKitTelemetryMonitorTests", dependencies: [
            "ScreenKitTelemetryMonitor", .product(name: "ScreenKit", package: "ScreenKit")
        ], resources: [.copy("Fixtures")])
    ]
)

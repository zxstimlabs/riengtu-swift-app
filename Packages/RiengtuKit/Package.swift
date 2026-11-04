// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RiengtuKit",
    // macOS too, so `swift test` runs on the Mac.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RiengtuKit", targets: ["RiengtuKit"]),
    ],
    targets: [
        .target(
            name: "RiengtuKit",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "RiengtuKitTests",
            dependencies: ["RiengtuKit"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)

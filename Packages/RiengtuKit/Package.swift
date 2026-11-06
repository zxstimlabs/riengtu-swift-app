// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RiengtuKit",
    // macOS too, so `swift test` runs on the Mac.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "RiengtuKit", targets: ["RiengtuKit"]),
    ],
    dependencies: [
        // SQLite, for the ledger's database. No network, no analytics: a library that runs SQL.
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.12.0"),
    ],
    targets: [
        .target(
            name: "RiengtuKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "RiengtuKitTests",
            dependencies: ["RiengtuKit", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
    ]
)

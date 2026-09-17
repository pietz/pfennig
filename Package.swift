// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pfennig",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Agent", targets: ["Agent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Schema, money, LocalDate, repository, validation rules and SQL tool.
        .target(
            name: "Core",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
            ],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        // Responses client, agent instructions, tool loop and file intake.
        .target(name: "Agent", dependencies: ["Core"]),
        .testTarget(name: "AgentTests", dependencies: ["Agent"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pfennig",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Kern", targets: ["Kern"]),
        .library(name: "Agent", targets: ["Agent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Schema, Geld, Datum, Repository, Prüfregeln, sql-Werkzeug.
        .target(
            name: "Kern",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "GRDBSQLite", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "KernTests", dependencies: ["Kern"]),
        // Responses-Client, Anleitung, Werkzeugschleife, Dateieingang.
        .target(name: "Agent", dependencies: ["Kern"]),
        .testTarget(name: "AgentTests", dependencies: ["Agent"]),
    ],
    swiftLanguageModes: [.v6]
)

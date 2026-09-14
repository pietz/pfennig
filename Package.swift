// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pfennig",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Database", targets: ["Database"]),
        .library(name: "DocumentStore", targets: ["DocumentStore"]),
        .library(name: "StatementImport", targets: ["StatementImport"]),
        .library(name: "ImportPipeline", targets: ["ImportPipeline"]),
        .library(name: "AI", targets: ["AI"]),
        .library(name: "Validation", targets: ["Validation"]),
        .library(name: "Tax", targets: ["Tax"]),
        .library(name: "Analysis", targets: ["Analysis"]),
        .library(name: "Export", targets: ["Export"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Pure value types. Depends on nothing.
        .target(name: "Domain"),

        // Persistence. Domain + GRDB only.
        .target(name: "Database", dependencies: ["Domain", .product(name: "GRDB", package: "GRDB.swift")]),

        // Archive folder, hashing, file copies.
        .target(name: "DocumentStore", dependencies: ["Domain"]),

        // No network, no database.
        .target(name: "Tax", dependencies: ["Domain"]),
        .target(name: "Validation", dependencies: ["Domain"]),

        // Domain only (see spec 22).
        .target(name: "AI", dependencies: ["Domain"], resources: [.process("Prompts")]),

        .target(name: "StatementImport", dependencies: ["Domain"]),

        .target(name: "Analysis", dependencies: ["Domain", "Database"]),
        .target(name: "Export", dependencies: ["Domain", "Database", "Tax"]),

        .target(name: "ImportPipeline", dependencies: [
            "Domain", "Database", "DocumentStore", "StatementImport", "AI", "Validation", "Tax",
        ]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "ExportTests", dependencies: ["Export", "Tax", "Domain"]),
        .testTarget(name: "DatabaseTests", dependencies: ["Analysis", "Database", "Domain"]),
        .testTarget(name: "DocumentStoreTests", dependencies: ["DocumentStore"]),
        .testTarget(name: "TaxTests", dependencies: ["Tax", "Domain"]),
        .testTarget(name: "ValidationTests", dependencies: ["Validation", "Domain"]),
        .testTarget(
            name: "ImportTests",
            dependencies: ["AI", "Database", "Domain", "DocumentStore", "ImportPipeline"]
        ),
        .testTarget(
            name: "BookkeepingTests",
            dependencies: ["Database", "Domain", "DocumentStore", "ImportPipeline"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

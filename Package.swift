// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pfennig",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Kern", targets: ["Kern"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Schema, Geld, Datum, Repository.
        .target(name: "Kern", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "KernTests", dependencies: ["Kern"]),
    ],
    swiftLanguageModes: [.v6]
)

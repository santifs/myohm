// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BioMessAppFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BioMessAppFeature",
            targets: ["BioMessAppFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../BioMessCorePackage")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BioMessAppFeature",
            dependencies: [
                .product(name: "BioMessCore", package: "BioMessCorePackage")
            ],
            exclude: [
                "Views/MeasurementDetailView.swift.backup"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BioMessAppFeatureTests",
            dependencies: [
                "BioMessAppFeature"
            ]
        ),
    ]
)

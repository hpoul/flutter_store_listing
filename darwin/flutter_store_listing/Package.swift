// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_store_listing",
    platforms: [
        .iOS("15.0"),
        // Flutter's own macOS floor. The review prompt needs macOS 13 for
        // `AppStore.requestReview(in:)` and falls back below that, rather than
        // raising the floor for a package whose other half is just a URL.
        .macOS("12.0")
    ],
    products: [
        .library(name: "flutter-store-listing", targets: ["flutter_store_listing"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_store_listing",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)

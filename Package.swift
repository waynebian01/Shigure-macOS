// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShigureCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ShigureCore", targets: ["ShigureCore"])
    ],
    targets: [
        .target(
            name: "ShigureCore",
            path: "Sources/ShigureCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ShigureCoreTests",
            dependencies: ["ShigureCore"],
            path: "Tests/ShigureCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)

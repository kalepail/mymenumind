// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyMenuMind",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MyMenuMind", targets: ["MyMenuMind"])
    ],
    targets: [
        .target(
            name: "MyMenuMindCore"
        ),
        .executableTarget(
            name: "MyMenuMind",
            dependencies: ["MyMenuMindCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "MyMenuMindCoreTests",
            dependencies: ["MyMenuMindCore"]
        )
    ]
)

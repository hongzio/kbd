// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kbd",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", exact: "0.4.5"),
    ],
    targets: [
        // Hangul composition engine: no AppKit/IMK dependency, unit tested.
        .target(
            name: "KbdCore",
            path: "Sources/KbdCore"
        ),
        // config.toml model, parsing and validation: no AppKit dependency, unit tested.
        .target(
            name: "KbdConfig",
            dependencies: [
                "KbdCore",
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ],
            path: "Sources/KbdConfig"
        ),
        .executableTarget(
            name: "kbd",
            dependencies: ["KbdCore", "KbdConfig"],
            path: "Sources/kbd",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        // Swift Testing (XCTest isn't available with Command Line Tools only).
        .testTarget(
            name: "KbdCoreTests",
            dependencies: ["KbdCore"],
            path: "Tests/KbdCoreTests"
        ),
        .testTarget(
            name: "KbdConfigTests",
            dependencies: ["KbdConfig"],
            path: "Tests/KbdConfigTests"
        ),
    ]
)

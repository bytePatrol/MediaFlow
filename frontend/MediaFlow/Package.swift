// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MediaFlow", targets: ["MediaFlow"]),
    ],
    targets: [
        .executableTarget(
            name: "MediaFlow",
            path: "MediaFlow",
            exclude: ["MediaFlow.entitlements", "Info.plist"],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)

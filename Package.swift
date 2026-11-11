// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "yoo-app-windows-manager",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "YooWindowsManager", targets: ["YooWindowsManager"]),
        .library(name: "YooWindowsManagerCore", targets: ["YooWindowsManagerCore"]),
    ],
    targets: [
        .target(
            name: "YooWindowsManagerCore",
            path: "Sources/YooWindowsManagerCore"
        ),
        .executableTarget(
            name: "YooWindowsManager",
            dependencies: ["YooWindowsManagerCore"],
            path: "Sources/YooWindowsManager"
        ),
        .testTarget(
            name: "YooWindowsManagerCoreTests",
            dependencies: ["YooWindowsManagerCore"],
            path: "Tests/YooWindowsManagerCoreTests"
        ),
    ]
)

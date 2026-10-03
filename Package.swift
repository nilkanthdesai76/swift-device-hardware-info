// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-device-hardware-info",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "DeviceHardwareInfo",
            targets: ["DeviceHardwareInfo"]
        ),
    ],
    targets: [
        .target(
            name: "DeviceHardwareInfo",
            dependencies: [],
            path: "Sources/DeviceHardwareInfo"
        ),
        .testTarget(
            name: "DeviceHardwareInfoTests",
            dependencies: ["DeviceHardwareInfo"],
            path: "Tests/DeviceHardwareInfoTests"
        ),
    ]
)

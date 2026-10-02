// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HWMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HWMonitor",
            path: "Sources/HWMonitor",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)

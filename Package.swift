// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PlasmaDrag",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PlasmaDrag",
            path: "Sources/PlasmaDrag",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlideNative",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .executable(name: "Slide", targets: ["Slide"])
    ],
    dependencies: [
        .package(path: "SlideCore")
    ],
    targets: [
        .executableTarget(
            name: "Slide",
            dependencies: [
                .product(name: "AppFeature", package: "SlideCore"),
                .product(name: "SlideDatabase", package: "SlideCore"),
                .product(name: "CommandBarFeature", package: "SlideCore"),
            ]
        )
    ]
)
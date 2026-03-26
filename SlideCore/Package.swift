// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlideCore",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        // Core functionality
        .library(name: "SlideDatabase", targets: ["SlideDatabase"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "SlideEditor", targets: ["SlideEditor"]),
        .library(name: "CommandPaletteCore", targets: ["CommandPaletteCore"]),
        // Code editor (CodeMirror 6 WKWebView)
        .library(name: "CodeMirrorEditor", targets: ["CodeMirrorEditor"]),
        // CLI / IPC
        .library(name: "SlideCLICore", targets: ["SlideCLICore"]),
        // Firebase services
        .library(name: "FirebaseServices", targets: ["FirebaseServices"]),
    ],
    dependencies: [
        // Essential dependencies only
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.25.2"
        ),
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.11.0"),
        .package(url: "https://github.com/pointfreeco/swift-sharing.git", from: "2.7.4"),
        // Preview: ObjectBox SPM (codegen requires Xcode steps; guarded by canImport)
        .package(url: "https://github.com/objectbox/objectbox-swift-spm.git", from: "5.2.0"),
        // Firebase dependencies
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.11.0"),
        // Kingfisher for async image loading and caching
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.8.0"),
        // STTextView for native markdown editor
        .package(url: "https://github.com/krzyzanowskim/STTextView.git", from: "2.3.6"),
        // Terminal emulator
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.12.0"),
        // Emoji picker
        .package(url: "https://github.com/danielsaidi/EmojiKit.git", from: "2.3.0"),
        // CLI argument parsing
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
    ],
    targets: [
        // Simplified Database
        .target(
            name: "SlideDatabase",
            dependencies: [
                "FirebaseServices",
                .product(name: "Dependencies", package: "swift-dependencies"),
                // Link the ObjectBox xcframework only when available for macOS
                .product(
                    name: "ObjectBox.xcframework",
                    package: "objectbox-swift-spm",
                    condition: .when(platforms: [.macOS])
                ),
            ],
            exclude: [
                "model-SlideDatabase.json"
            ],
            resources: [
                .process("DebugData.json")
            ]
        ),

        // Command Palette Core
        .target(
            name: "CommandPaletteCore",
            dependencies: [
                "SlideDatabase",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            path: "Sources/CommandPaletteCore",
            exclude: [
                "README.md"
            ]
        ),

        // Markdown Editor
        .target(
            name: "SlideEditor",
            dependencies: [
                .product(name: "STTextView", package: "STTextView")
            ],
            path: "Sources/SlideEditor"
        ),

        // Code Editor (CodeMirror 6)
        .target(
            name: "CodeMirrorEditor",
            dependencies: [],
            path: "Sources/CodeMirrorEditor",
            resources: [
                .process("Resources")
            ]
        ),

        // CLI / IPC Core
        .target(
            name: "SlideCLICore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/SlideCLICore"
        ),

        // App Feature
        .target(
            name: "AppFeature",
            dependencies: [
                "SlideDatabase",
                "SlideEditor",
                "CommandPaletteCore",
                "SlideCLICore",
                "CodeMirrorEditor",
                "FirebaseServices",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Sharing", package: "swift-sharing"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "EmojiKit", package: "EmojiKit"),
            ],
            path: "Sources/AppFeature",
            exclude: [
                "Views/Working/ContentViews/WebView/CLAUDE.md"
            ],
            resources: [
                .process("Fonts")
            ]
        ),

        // Firebase services target
        .target(
            name: "FirebaseServices",
            dependencies: [
                .product(name: "FirebaseAI", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseRemoteConfig", package: "firebase-ios-sdk"),
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/FirebaseServices"
        ),
        .testTarget(
            name: "SlideCoreTests",
            dependencies: [
                "AppFeature",
                "SlideDatabase",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
    ]
)

// Note: Removed dependencies:
// - ConfettiSwiftUI (no celebration transitions)
// - MilkdownEditor module (replaced by STTextView-based native editor)
// - swift-json-schema, swift-mustache, DSFQuickActionBar, MCP-related (previously removed)

//
//  SlideApp.swift
//  Slide
//
//  Created by Jordan Howlett on 9/5/25.
//

import AppFeature
import ComposableArchitecture
import Foundation
import Sharing
import SlideCLICore
import SlideDatabase
import SwiftUI
import FirebaseCore
import FirebaseServices
import Kingfisher
#if canImport(AppKit)
import AppKit
#endif

@main
struct SlideApp: App {
    static let store: StoreOf<SlideAppFeature> = Store(
        initialState: SlideAppFeature.State()
    ) {
        SlideAppFeature()
    }

    static var databaseURL: URL?
    static var mediaURL: URL?
    static let remoteConfig = RemoteConfigService()
    @MainActor static let commandServerBridge = CommandServerBridge()

    init() {
        // CLI mode: if invoked as "slide" (via symlink) or with --cli, run CLI and exit
        if SlideCLI.isCLIMode {
            SlideCLI.run() // exits the process
        }

        #if canImport(AppKit)
        // Disable AppKit's automatic window tabbing so View > "Show Tab Bar"
        // and "Show All Tabs" are not added to the menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif

        // Configure Firebase first
        FirebaseApp.configure()
        
        // Configure Kingfisher cache for favicons
        configureImageCache()
        
        // Register custom fonts
        SlideFont.registerFonts()

        // Initialize ObjectBox store (non-sandboxed macOS app)
        do {
            // Configure storage paths once and expose them
            // Don't override the default from StorageConfig - it already handles DEBUG
            try StorageConfig.ensureBaseDirectories()
            let dbURL = try StorageConfig.databaseURL()

            SlideApp.databaseURL = dbURL
            SlideApp.mediaURL = try? StorageConfig.mediaURL()

            try ObjectBoxDatabase.initialize(at: dbURL)
        } catch {
            print("Failed to initialize ObjectBox store:")
            print("Error: \(error)")
            print("Ensure the Application Support directory is writable and try again.")
            fatalError("Failed to initialize ObjectBox store: \(error)")
        }
        
        // Initialize Remote Config
        Task {
            await SlideApp.remoteConfig.start()
        }
        
        // Configure AI Service provider
        AIServiceProvider.shared.configure()
        
        // Log app launch
        AnalyticsService.logSessionStart()
        
        // Load debug data in DEBUG builds
        #if DEBUG
        Task {
            await DebugDataLoader.loadDebugDataIfNeeded()
            print("[SlideApp] Debug data loading initiated")
        }
        #endif

        // Start CLI socket server
        Self.commandServerBridge.start(
            dispatch: { command in
                Self.store.send(.cliCommand(command))
            },
            stateProvider: {
                let state = Self.store.withState { $0 }
                return (
                    objects: state.browser.objects,
                    projects: state.browser.projects,
                    activeProjectId: state.browser.activeProjectId
                )
            }
        )

        // Install CLI symlink
        CLIInstaller.installIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: Self.store)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .commands {
            SlideMenuCommands(store: Self.store)
            CommandGroup(replacing: .saveItem) { }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
    
    private func configureImageCache() {
        // Configure Kingfisher cache for favicons and images
        let cache = ImageCache.default
        
        // Memory cache: 100MB for favicons and images
        cache.memoryStorage.config.totalCostLimit = 100 * 1024 * 1024
        cache.memoryStorage.config.countLimit = 1000 // Max 1000 images in memory
        
        // Memory expiration: 30 minutes (favicons don't change often)
        cache.memoryStorage.config.expiration = .seconds(1800)
        
        // Disk cache: 200MB (favicons are small, this is plenty)
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024
        
        // Disk expiration: 7 days (favicons rarely change)
        cache.diskStorage.config.expiration = .days(7)
        
        // Configure downloader for better performance
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 10.0 // 10 seconds timeout for favicons
        
        print("[SlideApp] Configured Kingfisher cache - Memory: 100MB/1000 items, Disk: 200MB, Expiration: 30min/7days")
    }
}

struct SlideMenuCommands: Commands {
    let store: StoreOf<SlideAppFeature>

    var body: some Commands {
        // Override File menu items
        CommandGroup(replacing: .newItem) {
            Button("New Note") { store.send(.createNewNote) }
                .keyboardShortcut("N", modifiers: .command)
        }

        // Override close behavior in File menu
        CommandGroup(after: .newItem) {
            Divider()
            Button("Close Panel") { store.send(.closeCurrentObject) }
                .keyboardShortcut("W", modifiers: .command)
                .disabled(store.browser.visiblePanelIds.isEmpty)
        }

        CommandMenu("Object") {
            Button("New Tab") { store.send(.openCommandBarNewTab) }
                .keyboardShortcut("T", modifiers: .command)

            Button("Focus Filter Bar") { store.send(.focusFilterBar) }
                .keyboardShortcut("L", modifiers: .command)

            Button("Quick Switch Object") { store.send(.openCommandBarObjects) }
                .keyboardShortcut("P", modifiers: .command)

            Button("Switch Project") { store.send(.openCommandBarProjects) }
                .keyboardShortcut("P", modifiers: [.command, .shift])

            Divider()

            Button("Duplicate Tab") { store.send(.duplicateCurrentObject) }
                .keyboardShortcut("D", modifiers: .command)
                .disabled(store.browser.selectedObjectId == nil ||
                         store.browser.objects.first(where: { $0.uuidValue == store.browser.selectedObjectId })?.objectType != .link)

            Button("Copy Current URL") { store.send(.copyCurrentUrl) }
                .keyboardShortcut("C", modifiers: [.command, .shift])

            Divider()

            Button("Focus Panel Left") { store.send(.browser(.focusPanelLeft)) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Focus Panel Right") { store.send(.browser(.focusPanelRight)) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }

        CommandMenu("View") {
            Button("Toggle Command Bar") { store.send(.toggleCommandBar) }
                .keyboardShortcut("K", modifiers: .command)

            Divider()

            Button("Go Back") { store.send(.goBack) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Go Forward") { store.send(.goForward) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Reload") { store.send(.reload) }
                .keyboardShortcut("R", modifiers: .command)

            Divider()

            Button("Previous Object") { store.send(.browser(.selectPreviousObject)) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next Object") { store.send(.browser(.selectNextObject)) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Button("Zoom In") { store.send(.zoomIn) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { store.send(.zoomOut) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { store.send(.resetZoom) }
                .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Enter Focus Mode") { store.send(.browser(.toggleFullscreen)) }
                .keyboardShortcut("F", modifiers: [.command, .shift])

            Divider()

            Button("Toggle Sidebar") { store.send(.browser(.toggleSidebar)) }
                .keyboardShortcut("\\", modifiers: .command)
        }

        CommandMenu("Edit") {
            Button("Find") { store.send(.browser(.showFindBar)) }
                .keyboardShortcut("F", modifiers: .command)

            Divider()

            Button("Hide Find Bar") { store.send(.browser(.hideFindBar)) }
                .keyboardShortcut(.escape)
                .disabled(!store.browser.isFindBarVisible)
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") { store.send(.checkForUpdates) }
        }

        CommandMenu("Debug") {
            #if DEBUG
            Button("Reload Debug Data") {
                Task {
                    await DebugDataLoader.reloadDebugData()
                    store.send(.browser(.onAppear))
                }
            }
            .keyboardShortcut("R", modifiers: [.command, .option, .shift])

            Button("Clear All Data") {
                Task {
                    await DebugDataLoader.clearAllData()
                    store.send(.browser(.onAppear))
                }
            }
            .keyboardShortcut("C", modifiers: [.command, .option, .shift])

            Divider()
            #endif

            Button("Open Database Directory") {
                if let dbURL = SlideApp.databaseURL {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dbURL.path)
                }
            }
            .keyboardShortcut("D", modifiers: [.command, .shift])

            Divider()

            Button("Show Database Path") {
                if let dbURL = SlideApp.databaseURL {
                    print("Database path: \(dbURL.path)")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(dbURL.path, forType: .string)
                }
            }

            Divider()

            Button("Open Media Directory") {
                if let mediaURL = SlideApp.mediaURL {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mediaURL.path)
                }
            }
            Button("Show Media Path") {
                if let mediaURL = SlideApp.mediaURL {
                    print("Media path: \(mediaURL.path)")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(mediaURL.path, forType: .string)
                }
            }
        }
    }
}

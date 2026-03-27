import Foundation
import SwiftUI
import SlideDatabase

// MARK: - Slide App Commands

public enum SlideCommands {

    // MARK: - Object Commands

    public static let viewObjects = CommandDefinition(
        id: .init("view-objects"),
        title: "View Objects",
        keywords: ["object", "tab", "content", "browse", "switch"],
        icon: "folder",
        shortcut: "⌘P",
        activation: { _, scope in
            scope == .cmdK || scope == .cmdP
        },
        entry: .withProvider(title: "Objects", providerID: "slide.objects")
    )

    public static let closeObject = CommandDefinition(
        id: .init("close-object"),
        title: "Close Object",
        keywords: ["close", "tab", "object"],
        icon: "xmark.circle",
        shortcut: "⌘W",
        activation: { ctx, scope in
            ctx.currentObjectID != nil && (scope == .cmdK || scope == .cmdL)
        },
        entry: .direct(effect: .custom("browser.close-object"))
    )

    public static let duplicateTab = CommandDefinition(
        id: .init("duplicate-tab"),
        title: "Duplicate Tab",
        keywords: ["duplicate", "copy", "tab", "clone"],
        icon: "plus.square.on.square",
        shortcut: "⌘D",
        activation: { ctx, scope in
            ctx.currentObjectID != nil && (scope == .cmdK || scope == .cmdL)
        },
        entry: .direct(effect: .custom("browser.duplicate-object"))
    )

    public static let copyCurrentUrl = CommandDefinition(
        id: .init("copy-url"),
        title: "Copy Current URL",
        keywords: ["copy", "link", "url"],
        icon: "doc.on.doc",
        shortcut: "⌘⇧C",
        activation: { ctx, scope in
            ctx.currentObjectID != nil && (scope == .cmdK || scope == .cmdL)
        },
        entry: .direct(effect: .custom("browser.copy-url"))
    )

    // MARK: - Create Commands

    public static let createProject = CommandDefinition(
        id: .init("create-project"),
        title: "New Project",
        keywords: ["new", "create", "project", "add", "folder"],
        icon: "folder.badge.plus",
        shortcut: "⌘N",
        activation: { _, scope in scope == .cmdK },
        entry: .direct(effect: .custom("create.project"))
    )

    public static let createNote = CommandDefinition(
        id: .init("create-note"),
        title: "New Note",
        keywords: ["new", "create", "note", "add"],
        icon: "note.text.badge.plus",
        shortcut: "⇧⌘N",
        activation: { _, scope in scope == .cmdK },
        entry: .direct(effect: .custom("create.note"))
    )

    public static let createTerminal = CommandDefinition(
        id: .init("create-terminal"),
        title: "New Terminal",
        keywords: ["new", "terminal", "shell", "console"],
        icon: "terminal",
        activation: { _, scope in scope == .cmdK },
        entry: .direct(effect: .custom("create.terminal"))
    )

    // MARK: - Navigation Commands

    public static let goBack = CommandDefinition(
        id: .init("go-back"),
        title: "Go Back",
        keywords: ["back", "previous", "history"],
        icon: "chevron.left",
        shortcut: "⌘[",
        activation: { ctx, _ in ctx.currentObjectID != nil },
        entry: .direct(effect: .custom("browser.go-back"))
    )

    public static let goForward = CommandDefinition(
        id: .init("go-forward"),
        title: "Go Forward",
        keywords: ["forward", "next", "history"],
        icon: "chevron.right",
        shortcut: "⌘]",
        activation: { ctx, _ in ctx.currentObjectID != nil },
        entry: .direct(effect: .custom("browser.go-forward"))
    )

    public static let reload = CommandDefinition(
        id: .init("reload"),
        title: "Reload",
        keywords: ["refresh", "reload"],
        icon: "arrow.clockwise",
        shortcut: "⌘R",
        activation: { ctx, _ in ctx.currentObjectID != nil },
        entry: .direct(effect: .custom("browser.reload"))
    )

    // MARK: - UI Commands

    public static let toggleFullscreen = CommandDefinition(
        id: .init("toggle-fullscreen"),
        title: "Toggle Focus Mode",
        keywords: ["fullscreen", "focus", "zen"],
        icon: "arrow.up.left.and.down.right.magnifyingglass",
        activation: { _, scope in scope == .cmdK },
        entry: .direct(effect: .custom("browser.toggle-fullscreen"))
    )

    // MARK: - Project Commands

    public static let moveToProject = CommandDefinition(
        id: .init("move-to-project"),
        title: "Move to Project",
        keywords: ["move", "project", "assign", "organize"],
        icon: "folder",
        activation: { ctx, scope in
            ctx.currentObjectID != nil && scope == .cmdK
        },
        entry: .withProvider(title: "Move to Project", providerID: "slide.moveToProject")
    )

    // MARK: - System Commands

    public static let toggleDarkMode = CommandDefinition(
        id: .init("toggle-dark-mode"),
        title: "Toggle Dark Mode",
        keywords: ["dark", "light", "theme", "appearance"],
        icon: "moon.circle",
        activation: { _, _ in true },
        entry: .direct(effect: .toggleDarkMode)
    )

    public static let showSettings = CommandDefinition(
        id: .init("show-settings"),
        title: "Settings",
        keywords: ["settings", "preferences", "config"],
        icon: "gearshape",
        activation: { _, scope in scope == .cmdK },
        entry: .direct(effect: .showSettings)
    )

    // MARK: - Quick Links (AI & Productivity)

    public static let openChatGPT = CommandDefinition(
        id: .init("open-chatgpt"),
        title: "ChatGPT",
        keywords: ["chatgpt", "openai", "ai", "chat"],
        icon: "asset:ChatGPT",
        activation: { _, scope in scope == .cmdT || scope == .cmdL },
        entry: .direct(effect: .openURL("https://chat.openai.com"))
    )

    public static let openClaude = CommandDefinition(
        id: .init("open-claude"),
        title: "Claude",
        keywords: ["claude", "anthropic", "ai"],
        icon: "asset:Claude",
        activation: { _, scope in scope == .cmdT || scope == .cmdL },
        entry: .direct(effect: .openURL("https://claude.ai"))
    )

    public static let openGitHub = CommandDefinition(
        id: .init("open-github"),
        title: "GitHub",
        keywords: ["github", "code", "git"],
        icon: "asset:GitHub",
        activation: { _, scope in scope == .cmdT || scope == .cmdL },
        entry: .direct(effect: .openURL("https://github.com"))
    )

    public static let openNotion = CommandDefinition(
        id: .init("open-notion"),
        title: "Notion",
        keywords: ["notion", "notes", "docs"],
        icon: "asset:Notion",
        activation: { _, scope in scope == .cmdT || scope == .cmdL },
        entry: .direct(effect: .openURL("https://notion.so"))
    )

    // MARK: - Contextual Object Commands

    public static let findOnPage = CommandDefinition(
        id: .init("find-on-page"),
        title: "Find on Page",
        keywords: ["find", "search", "page", "text"],
        icon: "magnifyingglass",
        shortcut: "⌘F",
        activation: { ctx, scope in
            ctx.currentObjectID != nil && scope == .cmdK
        },
        entry: .direct(effect: .custom("browser.find-on-page"))
    )

    // MARK: - All Commands

    public static func all() -> [CommandDefinition] {
        [
            // Current Object Actions
            copyCurrentUrl,
            duplicateTab,
            moveToProject,
            closeObject,
            findOnPage,

            // Create
            createProject,
            createNote,
            createTerminal,

            // View Commands
            viewObjects,

            // Navigation
            goBack,
            goForward,
            reload,

            // UI Controls
            toggleDarkMode,
            toggleFullscreen,
            showSettings,

            // Quick Links
            openChatGPT,
            openClaude,
            openGitHub,
            openNotion
        ]
    }
}

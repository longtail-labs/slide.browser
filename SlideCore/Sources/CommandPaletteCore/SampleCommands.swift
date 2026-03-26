import Foundation

public enum SamplePaletteCommands {
    public static func definitions() -> [CommandDefinition] {
        [viewTasks, viewObjects, quickLinksNewTab, webSearch, claude, emojiPicker]
    }

    // View Tasks -> provider
    public static let viewTasks = CommandDefinition(
        id: .init("viewTasks"),
        title: "View Tasks",
        keywords: ["task","todo"],
        icon: "checkmark.circle",
        activation: { _, scope in
            // Show in general, cmdP, and cmdShiftP scopes
            switch scope { case .cmdK, .cmdP, .cmdShiftP: return true; default: return false }
        },
        entry: .withProvider(title: "Tasks", providerID: "tasks")
    )

    // Web Search (e.g., cmd-L scope)
    public static let webSearch = CommandDefinition(
        id: .init("google"),
        title: "Search Google",
        keywords: ["web","google"],
        icon: "magnifyingglass",
        activation: { _, scope in scope == .cmdL || scope == .cmdT },
        entry: .withProvider(title: "Google", providerID: "google")
    )

    // Claude input workflow
    public static let claude = CommandDefinition(
        id: .init("claude"),
        title: "Ask Claude",
        keywords: ["ai","assistant"],
        icon: "🧠",
        activation: { ctx, scope in
            let allowed: Set<PaletteScope> = [.cmdL, .cmdP, .cmdK]
            return allowed.contains(scope) && (ctx.currentObjectID != nil || ctx.route == "newObject")
        },
        entry: .workflow(
            title: "Ask Claude",
            steps: [
                .input(.init(title: "Prompt", placeholder: "Describe what you need…"), actionKey: "claude.prompt")
            ]
        )
    )

    // Objects (Cmd+P)
    public static let viewObjects = CommandDefinition(
        id: .init("viewObjects"),
        title: "View Objects",
        keywords: ["object","tab","content"],
        icon: "folder",
        activation: { _, scope in scope == .cmdP },
        entry: .withProvider(title: "Objects", providerID: "objects")
    )

    // Quick Links (Cmd+T)
    public static let quickLinksNewTab = CommandDefinition(
        id: .init("quickLinks"),
        title: "Quick Links",
        keywords: ["links","web"],
        icon: "link.circle",
        activation: { _, scope in scope == .cmdT },
        entry: .withProvider(title: "Links", providerID: "quicklinks")
    )

    // Emoji Picker (Cmd+K)
    public static let emojiPicker = CommandDefinition(
        id: .init("emojiPicker"),
        title: "Emoji Picker",
        keywords: ["emoji"],
        icon: "😀",
        activation: { _, scope in scope == .cmdK },
        entry: .withProvider(title: "Emoji", providerID: "emoji")
    )
}

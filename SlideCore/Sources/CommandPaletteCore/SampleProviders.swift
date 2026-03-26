import Foundation

// MARK: - Shared helpers

func relativeLabel(minutesAgo: Int) -> String {
    if minutesAgo < 1 { return "now" }
    if minutesAgo < 60 { return "\(minutesAgo)m" }
    let hours = minutesAgo / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    return "\(days)d"
}

// MARK: - Sample Providers

public struct TasksProvider: CommandProvider {
    public init() {}

    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task { @MainActor in
                // Generate a long list (250) for scrolling tests
                let base = (1...250).map { idx in
                    ("task-\(idx)", "Task #\(idx)", idx % 2 == 0 ? "Project A" : "Project B")
                }

                let filtered = base.filter { t in
                    guard let q = query, !q.isEmpty else { return true }
                    return t.1.localizedCaseInsensitiveContains(q)
                }

                let items = filtered.enumerated().map { (idx, tuple) in
                    let (id, title, project) = tuple

                    // Sub-commands for each task
                    let subItems: [CommandItem] = [
                        CommandItem(
                            id: "open-\(id)",
                            title: "Open Task",
                            subtitle: nil,
                            icon: "arrow.right.circle",
                            transition: .effect(.openTask(id))
                        ),
                        CommandItem(
                            id: "rename-\(id)",
                            title: "Rename Task",
                            subtitle: nil,
                            icon: "pencil",
                            transition: .pushPane(
                                CommandPaneSpec(
                                    title: "Rename Task",
                                    kind: .input(
                                        TextInputSpec(title: "New name", placeholder: title, initial: title),
                                        actionKey: "task.rename.\(id)"
                                    )
                                )
                            )
                        )
                    ]

                    let minutesAgo = (idx * 7) % 600 // up to ~10h
                    return CommandItem(
                        id: id,
                        title: title,
                        subtitle: project,
                        icon: "checkmark.circle",
                        metadata: relativeLabel(minutesAgo: minutesAgo),
                        transition: .pushStaticList(title: "Task: \(title)", items: subItems)
                    )
                }
                continuation.yield(items)
                continuation.finish()
            }
        }
    }
}

public struct GoogleProvider: CommandProvider {
    public init() {}
    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task {
                let q = (query ?? "").trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { continuation.yield([]); continuation.finish(); return }
                let items = (1...5).map { i in
                    CommandItem(
                        id: "g-\(i)",
                        title: "Result \(i) for \"\(q)\"",
                        subtitle: "example.com/\(i)",
                        icon: "globe",
                        transition: .effect(.openURL("https://www.google.com/search?q=\(q)"))
                    )
                }
                continuation.yield(items)
                continuation.finish()
            }
        }
    }
}

public struct QuickLinksProvider: CommandProvider {
    public init() {}
    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task { @MainActor in
                let links: [(String, String, String)] = [
                    ("GitHub", "https://github.com", "https://github.githubassets.com/favicons/favicon.png"),
                    ("Discord", "https://discord.com", "asset:Discord"),
                    ("YouTube", "https://youtube.com", "https://www.youtube.com/s/desktop/fe2e0174/img/favicon_144x144.png"),
                    ("Reddit", "https://reddit.com", "https://www.redditstatic.com/desktop2x/img/favicon/apple-icon-120x120.png"),
                    ("OpenAI", "https://openai.com", "https://openai.com/favicon.ico"),
                ]

                let filtered = links.filter { title, _, _ in
                    guard let q = query, !q.isEmpty else { return true }
                    return title.localizedCaseInsensitiveContains(q)
                }

                let items = filtered.enumerated().map { (idx, entry) in
                    let (title, url, icon) = entry
                    return CommandItem(
                        id: "ql-\(idx)",
                        title: title,
                        subtitle: url,
                        icon: icon,
                        transition: .effect(.openURL(url))
                    )
                }
                continuation.yield(items)
                continuation.finish()
            }
        }
    }
}

public struct ObjectsProvider: CommandProvider {
    public init() {}
    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task { @MainActor in
                let objects: [(String, String, String)] = (1...50).map { i in
                    if i % 3 == 0 { return ("obj-\(i)", "PR #\(100 + i)", "https://github.githubassets.com/favicons/favicon.png") }
                    if i % 3 == 1 { return ("obj-\(i)", "Discord Channel #\(i)", "asset:Discord") }
                    return ("obj-\(i)", "PDF Report #\(i)", "doc.text")
                }

                let filtered = objects.filter { _, title, _ in
                    guard let q = query, !q.isEmpty else { return true }
                    return title.localizedCaseInsensitiveContains(q)
                }

                let items = filtered.enumerated().map { (idx, element) in
                    let (id, title, icon) = element
                    let minutesAgo = (idx * 11) % 1440 // up to ~1 day
                    let actions: [CommandItem] = [
                        CommandItem(id: "open-\(id)", title: "Open", subtitle: nil, icon: "arrow.right.circle", transition: .effect(.custom("object.open", payload: ["id": id]))),
                        CommandItem(id: "copy-\(id)", title: "Copy Link", subtitle: nil, icon: "link", transition: .effect(.custom("object.copyLink", payload: ["id": id]))),
                        CommandItem(id: "close-\(id)", title: "Close", subtitle: nil, icon: "xmark.circle", transition: .effect(.custom("object.close", payload: ["id": id])))
                    ]
                    return CommandItem(id: id, title: title, subtitle: "Object", icon: icon, metadata: relativeLabel(minutesAgo: minutesAgo), transition: .pushStaticList(title: title, items: actions))
                }
                continuation.yield(items)
                continuation.finish()
            }
        }
    }
}

// EmojiProvider removed — EmojiKit dependency no longer used

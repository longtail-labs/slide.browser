import Foundation
import SlideDatabase
import Dependencies

// MARK: - Google Suggestions Helper

private func fetchGoogleSuggestions(for query: String) async -> [String]? {
    guard !query.isEmpty,
          let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        return nil
    }

    let urlString = "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encodedQuery)"
    guard let url = URL(string: urlString) else { return nil }

    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        if let json = try JSONSerialization.jsonObject(with: data) as? [Any],
           json.count >= 2,
           let suggestions = json[1] as? [String] {
            return suggestions
        }
    } catch {
        print("[GoogleSuggestions] Error: \(error)")
    }

    return nil
}

// MARK: - Helper for relative time

private func relativeTime(from date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    let minutes = Int(interval / 60)

    if minutes < 1 { return "now" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    return "\(days)d"
}

// MARK: - Slide All Objects Provider (replaces task-scoped provider)

public struct SlideAllObjectsProvider: CommandProvider {
    @Dependency(\.slideDatabase) var database

    public init() {}

    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task {
                do {
                    let allObjects = try await database.fetchAllObjects()

                    let filtered: [TaskObject]
                    if let q = query, !q.isEmpty {
                        filtered = allObjects.filter { obj in
                            let title = obj.title ?? ""
                            let content = obj.content ?? ""
                            let url = obj.url?.absoluteString ?? ""
                            return title.localizedCaseInsensitiveContains(q) ||
                                   content.localizedCaseInsensitiveContains(q) ||
                                   url.localizedCaseInsensitiveContains(q)
                        }
                    } else {
                        filtered = allObjects
                    }

                    // Sort by last accessed
                    let sorted = filtered.sorted { a, b in
                        let ad = a.lastAccessedAt ?? .distantPast
                        let bd = b.lastAccessedAt ?? .distantPast
                        return ad > bd
                    }

                    let items = sorted.map { obj in
                        let metadata = obj.lastAccessedAt.map { relativeTime(from: $0) }
                        let icon: String = {
                            if obj.kind == .link, let favicon = obj.favicon, !favicon.isEmpty { return favicon }
                            switch obj.kind {
                            case .link: return "globe"
                            case .pdf: return "doc.fill"
                            case .note: return "note.text"
                            case .image: return "photo"
                            case .video: return "play.rectangle.fill"
                            case .audio: return "speaker.wave.2"
                            case .terminal: return "terminal"
                            case .codeEditor: return "curlybraces"
                            case .group: return "folder"
                            }
                        }()

                        return CommandItem(
                            id: obj.uuid,
                            title: obj.title ?? "Untitled",
                            subtitle: obj.url?.absoluteString ?? obj.content ?? "",
                            icon: icon,
                            metadata: metadata,
                            transition: .effect(.custom("object.select", payload: ["id": obj.uuid]))
                        )
                    }

                    continuation.yield(Array(items))
                    continuation.finish()
                } catch {
                    continuation.yield([])
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - Move to Project Provider

public struct SlideMoveToProjectProvider: CommandProvider {
    @Dependency(\.slideDatabase) var database

    public init() {}

    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task {
                do {
                    let projects = try await database.fetchAllProjects()
                    let q = (query ?? "").trimmingCharacters(in: .whitespaces)

                    let filtered: [OBXProject]
                    if q.isEmpty {
                        filtered = projects
                    } else {
                        filtered = projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
                    }

                    var items: [CommandItem] = []

                    for project in filtered {
                        let objectId = context.currentObjectID ?? ""
                        items.append(CommandItem(
                            id: "project-\(project.uuid)",
                            title: "\(project.icon) \(project.name)",
                            subtitle: "Move to project",
                            icon: "folder",
                            transition: .effect(.custom("project.assign", payload: [
                                "objectId": objectId,
                                "projectId": project.uuid
                            ]))
                        ))
                    }

                    // Option to create a new project
                    if !q.isEmpty {
                        let exactMatch = projects.contains(where: { $0.name.caseInsensitiveCompare(q) == .orderedSame })
                        if !exactMatch {
                            items.append(CommandItem(
                                id: "project-create-\(q)",
                                title: "Create project '\(q)'",
                                subtitle: "Create new project and move object",
                                icon: "plus.circle",
                                transition: .effect(.custom("project.create-and-assign", payload: [
                                    "objectId": context.currentObjectID ?? "",
                                    "name": q
                                ]))
                            ))
                        }
                    }

                    continuation.yield(items)
                    continuation.finish()
                } catch {
                    continuation.yield([])
                    continuation.finish()
                }
            }
        }
    }
}

// MARK: - Quick Links Provider (for cmd-T)

public struct SlideQuickLinksProvider: CommandProvider {
    public init() {}

    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task {
                let q = (query ?? "").trimmingCharacters(in: .whitespaces)

                var items: [CommandItem] = []

                // Create actions
                let createActions: [(String, String, String, String, [String])] = [
                    ("New Note", "Create a new note", "note.text.badge.plus", "create.note", ["note", "write", "text"]),
                    ("New Terminal", "Open a terminal session", "terminal", "create.terminal", ["terminal", "shell", "console"]),
                ]
                for (title, subtitle, icon, actionKey, keywords) in createActions {
                    if q.isEmpty || title.localizedCaseInsensitiveContains(q)
                        || keywords.contains(where: { $0.localizedCaseInsensitiveContains(q) }) {
                        items.append(CommandItem(
                            id: "quicklink-\(actionKey)",
                            title: title,
                            subtitle: subtitle,
                            icon: icon,
                            transition: .effect(.custom(actionKey))
                        ))
                    }
                }

                let links: [(String, String, String)] = [
                    ("ChatGPT", "https://chat.openai.com", "asset:ChatGPT"),
                    ("Claude", "https://claude.ai", "asset:Claude"),
                    ("Perplexity", "https://perplexity.ai", "asset:Perplexity"),
                    ("Google", "https://google.com", "asset:Google"),
                    ("GitHub", "https://github.com", "asset:GitHub"),
                    ("Notion", "https://notion.so", "asset:Notion"),
                    ("Linear", "https://linear.app", "asset:Linear"),
                    ("Google Docs", "https://docs.google.com", "asset:GoogleDocs"),
                    ("Google Sheets", "https://sheets.google.com", "asset:GoogleSheets"),
                    ("Google Calendar", "https://calendar.google.com", "asset:GoogleCalendar"),
                    ("Reddit", "https://reddit.com", "asset:Reddit"),
                    ("X (Twitter)", "https://x.com", "asset:X"),
                    ("Discord", "https://discord.com/app", "asset:Discord"),
                    ("YouTube", "https://youtube.com", "asset:YouTube"),
                    ("Spotify", "https://open.spotify.com", "asset:Spotify"),
                    ("Hacker News", "https://news.ycombinator.com", "asset:YC")
                ]

                let filteredLinks = links.filter { title, _, _ in
                    guard !q.isEmpty else { return true }
                    return title.localizedCaseInsensitiveContains(q)
                }

                for (title, url, icon) in filteredLinks {
                    items.append(CommandItem(
                        id: "quicklink-\(title)",
                        title: title,
                        subtitle: url,
                        icon: icon,
                        transition: .effect(.openURL(url))
                    ))
                }

                if !q.isEmpty {
                    if let detectedURL = SlideQuickInputParser.detectedURL(from: q) {
                        items.insert(CommandItem(
                            id: "goto-url",
                            title: "Go to \(detectedURL.host ?? detectedURL.absoluteString)",
                            subtitle: detectedURL.absoluteString,
                            icon: "arrow.right.circle",
                            transition: .effect(.openURL(detectedURL.absoluteString))
                        ), at: 0)
                    }

                    let searchUrl = "https://www.google.com/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)"
                    items.append(CommandItem(
                        id: "google-search",
                        title: "Search Google for '\(q)'",
                        subtitle: "google.com",
                        icon: "magnifyingglass",
                        transition: .effect(.openURL(searchUrl))
                    ))
                }

                continuation.yield(items)

                if !q.isEmpty, let suggestions = await fetchGoogleSuggestions(for: q) {
                    var enriched = items
                    for suggestion in suggestions.prefix(5) {
                        let suggestionUrl = "https://www.google.com/search?q=\(suggestion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? suggestion)"
                        enriched.append(CommandItem(
                            id: "suggestion-\(suggestion)",
                            title: suggestion,
                            subtitle: "Google suggestion",
                            icon: "magnifyingglass.circle",
                            transition: .effect(.openURL(suggestionUrl))
                        ))
                    }
                    continuation.yield(enriched)
                }

                continuation.finish()
            }
        }
    }
}

// MARK: - Web Search Provider

public struct SlideWebSearchProvider: CommandProvider {
    public init() {}

    public func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]> {
        AsyncStream { continuation in
            Task {
                let q = (query ?? "").trimmingCharacters(in: .whitespaces)

                guard !q.isEmpty else {
                    let defaultItems = [
                        CommandItem(
                            id: "search-google",
                            title: "Google",
                            subtitle: "Search with Google",
                            icon: "magnifyingglass",
                            transition: .effect(.openURL("https://google.com"))
                        ),
                        CommandItem(
                            id: "search-youtube",
                            title: "YouTube",
                            subtitle: "Search YouTube",
                            icon: "play.rectangle",
                            transition: .effect(.openURL("https://youtube.com"))
                        )
                    ]
                    continuation.yield(defaultItems)
                    continuation.finish()
                    return
                }

                var items: [CommandItem] = []

                if let detectedURL = SlideQuickInputParser.detectedURL(from: q) {
                    let goToTransition: CommandTransitionSpec = context.currentObjectID != nil
                        ? .effect(.updateCurrentURL(detectedURL.absoluteString))
                        : .effect(.openURL(detectedURL.absoluteString))

                    items.append(CommandItem(
                        id: "goto-url",
                        title: "Go to \(detectedURL.host ?? detectedURL.absoluteString)",
                        subtitle: detectedURL.absoluteString,
                        icon: "arrow.right.circle",
                        transition: goToTransition
                    ))
                }

                let searchUrl = "https://www.google.com/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)"
                items.append(CommandItem(
                    id: "google-search",
                    title: "Search Google for '\(q)'",
                    subtitle: "google.com",
                    icon: "magnifyingglass",
                    transition: context.currentObjectID != nil
                        ? .effect(.updateCurrentURL(searchUrl))
                        : .effect(.openURL(searchUrl))
                ))

                continuation.yield(items)

                if let suggestions = await fetchGoogleSuggestions(for: q) {
                    var enriched = items
                    for suggestion in suggestions {
                        let suggestionUrl = "https://www.google.com/search?q=\(suggestion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? suggestion)"
                        enriched.append(CommandItem(
                            id: "suggestion-\(suggestion)",
                            title: suggestion,
                            subtitle: "Google suggestion",
                            icon: "magnifyingglass.circle",
                            transition: context.currentObjectID != nil
                                ? .effect(.updateCurrentURL(suggestionUrl))
                                : .effect(.openURL(suggestionUrl))
                        ))
                    }
                    continuation.yield(enriched)
                }

                continuation.finish()
            }
        }
    }
}

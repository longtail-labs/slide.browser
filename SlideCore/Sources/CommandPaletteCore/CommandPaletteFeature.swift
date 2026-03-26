import Foundation
import ComposableArchitecture

// MARK: - Cancel IDs
private enum CancelID {
    case queryDebounce
    case providerStream
}

public struct CommandPaletteDependencyKey: DependencyKey {
    public static var liveValue: CommandRegistry = .init()
}

public extension DependencyValues {
    var commandRegistry: CommandRegistry {
        get { self[CommandPaletteDependencyKey.self] }
        set { self[CommandPaletteDependencyKey.self] = newValue }
    }
}

@Reducer
public struct CommandPaletteFeature {
    @ObservableState
    public struct State {
        public var isPresented: Bool = false
        public var scope: PaletteScope = .cmdK
        public var context: PaletteContext = .init()
        public var query: String = ""
        public var panes: [CommandPane] = []
        public var preselectedCommandID: CommandID?
        public var initialQuery: String? // For pre-filling query on open
        public var closeOnFirstEscape: Bool = false // Close instead of pop when launched directly into a subcommand
        // For ⌘P: all objects (unscoped) so we can toggle scope on/off
        public var unscopedItems: [CommandItem]? = nil

        public init() {}

        public var currentPaneIndex: Int? { panes.indices.last }
        
        // Check if current pane is in input mode
        public var isInputMode: Bool {
            guard let idx = currentPaneIndex else { return false }
            if case .input = panes[idx].kind { return true }
            return false
        }
        
        // Get the input spec for the current pane if in input mode
        public var currentInputSpec: (spec: TextInputSpec, actionKey: String)? {
            guard let idx = currentPaneIndex else { return nil }
            if case let .input(spec, actionKey) = panes[idx].kind {
                return (spec, actionKey)
            }
            return nil
        }
    }

    public enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)

        // Lifecycle
        case open(scope: PaletteScope, preselect: CommandID?, initialQuery: String? = nil)
        case openWithProvider(scope: PaletteScope, title: String, providerID: String, initialQuery: String? = nil)
        case close
        case updateContext(PaletteContext)

        // Querying
        case setQuery(String)
        case debouncedSetQuery(String)
        case refreshEligibleCommands

        // Selection / Navigation
        case selectTopCommand(CommandID)
        case selectItem(paneIndex: Int, itemID: String)
        case moveSelection(paneIndex: Int, delta: Int)
        case setSelection(paneIndex: Int, index: Int)
        case submitInputPane // Submit the current input pane with query as value
        case popPane
        case clearProjectScope // Remove project filter to show all objects

        // Provider streaming
        case startProvider(paneIndex: Int, providerID: String)
        case receiveProviderItems(paneIndex: Int, items: [CommandItem])

        // Delegate
        case delegate(DelegateAction)
    }

    public enum DelegateAction: Sendable, Equatable {
        case effectTriggered(CommandEffect)
        case didClose
    }

    @Dependency(\.slideCommandRegistry) var registry

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .open(scope, preselect, initialQuery):
                let startTime = CFAbsoluteTimeGetCurrent()
                state.isPresented = true
                state.scope = scope
                state.preselectedCommandID = preselect
                state.query = initialQuery ?? ""
                state.initialQuery = initialQuery
                state.closeOnFirstEscape = false
                state.panes = []

                // Build top-level pane from eligible commands
                let eligible = registry.eligible(for: state.context, scope: scope)
                let items = self.makeTopItems(from: eligible)
                state.panes = [CommandPane(title: "Commands", kind: .list(), items: items)]
                
                let openTime = CFAbsoluteTimeGetCurrent() - startTime
                print("[CommandPalette] Opened with \(eligible.count) commands in \(String(format: "%.3f", openTime))s")

                if let pre = preselect {
                    return .send(.selectTopCommand(pre))
                }
                return .none
                
            case let .openWithProvider(scope, title, providerID, initialQuery):
                let startTime = CFAbsoluteTimeGetCurrent()
                state.isPresented = true
                state.scope = scope
                state.query = initialQuery ?? ""
                state.initialQuery = initialQuery
                // Close on first escape for quick-switch scopes
                state.closeOnFirstEscape = (scope == .cmdP || scope == .cmdShiftP)
                
                // Create pane for provider results (no placeholder to avoid flicker)
                let pane = CommandPane(title: title, kind: .list(providerID: providerID))
                state.panes = [pane]

                // Pre-seed with instant items for known providers to avoid perceived latency
                if let seed = self.makeInitialItemsIfAvailable(providerID: providerID, query: state.query, context: state.context) {
                    state.panes[0].items = seed
                }
                
                let setupTime = CFAbsoluteTimeGetCurrent() - startTime
                print("[CommandPalette] openWithProvider - scope: \(scope), title: \(title), provider: \(providerID), query: '\(initialQuery ?? "")' (setup: \(String(format: "%.3f", setupTime))s)")
                
                // Start the provider immediately
                return .send(.startProvider(paneIndex: 0, providerID: providerID))

            case .close:
                state.isPresented = false
                state.panes = []
                return .send(.delegate(.didClose))

            case let .updateContext(ctx):
                state.context = ctx
                return .send(.refreshEligibleCommands)

            case .refreshEligibleCommands:
                guard let first = state.panes.first, case .list = first.kind else { return .none }
                let eligible = registry.eligible(for: state.context, scope: state.scope)
                let items = self.makeTopItems(from: eligible)
                state.panes[0].items = self.filter(items: items, query: state.query)
                return .none

            case let .setQuery(q):
                state.query = q
                // Debounce the query to avoid restarting providers too frequently
                return .send(.debouncedSetQuery(q))
                    .debounce(id: CancelID.queryDebounce, for: .milliseconds(150), scheduler: DispatchQueue.main)
                
            case let .debouncedSetQuery(q):
                guard let idx = state.currentPaneIndex else { return .none }
                switch state.panes[idx].kind {
                case .list(let providerID):
                    if let providerID = providerID {
                        // Restart provider for this pane
                        return .send(.startProvider(paneIndex: idx, providerID: providerID))
                    } else {
                        // For static lists, re-filter from a canonical source
                        // Root pane (idx == 0) refreshes from registry. Pushed static lists use sourceItems.
                        if idx == 0 {
                            let eligible = registry.eligible(for: state.context, scope: state.scope)
                            let allItems = self.makeTopItems(from: eligible)
                            state.panes[idx].items = filter(items: allItems, query: q)
                        } else {
                            let base = state.panes[idx].sourceItems ?? state.panes[idx].items
                            // If query is empty, restore full list
                            if q.isEmpty {
                                state.panes[idx].items = base
                            } else {
                                state.panes[idx].items = filter(items: base, query: q)
                            }
                        }
                        return .none
                    }
                case .input:
                    // Input panes manage their own text in the view; query filters nothing
                    return .none
                }

            case let .selectTopCommand(id):
                guard state.panes.indices.contains(0) else { return .none }
                guard let item = state.panes[0].items.first(where: { $0.id == id.rawValue }) else { return .none }
                return self.apply(transition: item.transition, state: &state)

            case let .selectItem(paneIndex, itemID):
                guard state.panes.indices.contains(paneIndex) else { return .none }
                guard let item = state.panes[paneIndex].items.first(where: { $0.id == itemID }) else { return .none }
                return self.apply(transition: item.transition, state: &state)

            case let .moveSelection(paneIndex, delta):
                guard state.panes.indices.contains(paneIndex) else { return .none }
                var pane = state.panes[paneIndex]
                guard !pane.items.isEmpty else { return .none }
                let newIndex = max(0, min(pane.selectedIndex + delta, pane.items.count - 1))
                pane.selectedIndex = newIndex
                state.panes[paneIndex] = pane
                return .none

            case let .setSelection(paneIndex, index):
                guard state.panes.indices.contains(paneIndex) else { return .none }
                var pane = state.panes[paneIndex]
                guard pane.items.indices.contains(index) else { return .none }
                pane.selectedIndex = index
                state.panes[paneIndex] = pane
                return .none
            
            case .submitInputPane:
                guard let idx = state.currentPaneIndex else { return .none }
                let pane = state.panes[idx]
                if case let .input(_, actionKey) = pane.kind {
                    let value = state.query
                    print("[CommandPalette] Submitting input: actionKey=\(actionKey), value=\(value)")
                    
                    // Send the effect and then navigate back or close
                    let effect = Effect<Action>.send(.delegate(.effectTriggered(.custom(actionKey, payload: ["value": value]))))
                    
                    // If there are multiple panes, go back; otherwise close
                    if state.panes.count > 1 {
                        // Pop the input pane and reset query
                        _ = state.panes.removeLast()
                        state.query = ""
                        print("[CommandPalette] Popped input pane, returning to previous pane")
                        return effect
                    } else {
                        print("[CommandPalette] No previous pane, closing palette")
                        return .concatenate(effect, .send(.close))
                    }
                }
                return .none

            case .popPane:
                if !state.panes.isEmpty { _ = state.panes.removeLast() }
                if state.panes.isEmpty { return .send(.close) }
                // Reset search query when going back to a different pane
                state.query = ""
                // If going back to the root pane, refresh the command list with no filter
                if state.panes.count == 1, state.panes[0].kind == .list(providerID: nil) {
                    let eligible = registry.eligible(for: state.context, scope: state.scope)
                    let items = self.makeTopItems(from: eligible)
                    state.panes[0].items = items
                }
                return .none

            case .clearProjectScope:
                // Remove project scope and show all objects
                state.context.scopeProjectId = nil
                state.context.scopeProjectName = nil
                if let allItems = state.unscopedItems, let idx = state.currentPaneIndex {
                    state.panes[idx].items = allItems
                    state.panes[idx].sourceItems = allItems
                    state.panes[idx].selectedIndex = 0
                    // Re-apply current query filter
                    if !state.query.isEmpty {
                        state.panes[idx].items = filter(items: allItems, query: state.query)
                    }
                }
                return .none

            case let .startProvider(paneIndex, providerID):
                guard state.panes.indices.contains(paneIndex) else { 
                    print("[CommandPalette] Invalid pane index: \(paneIndex)")
                    return .none 
                }
                let q = state.query
                let ctx = state.context
                guard let provider = registry.provider(for: providerID) else { 
                    print("[CommandPalette] Provider not found: \(providerID)")
                    return .none 
                }
                let providerStartTime = CFAbsoluteTimeGetCurrent()
                print("[CommandPalette] Starting provider: \(providerID) with query: '\(q)'")
                return .run { send in
                    for await batch in provider.start(query: q, context: ctx) {
                        let elapsed = CFAbsoluteTimeGetCurrent() - providerStartTime
                        print("[CommandPalette] Received \(batch.count) items from provider: \(providerID) after \(String(format: "%.3f", elapsed))s")
                        await send(.receiveProviderItems(paneIndex: paneIndex, items: batch))
                    }
                }
                .cancellable(id: CancelID.providerStream, cancelInFlight: true)

            case let .receiveProviderItems(paneIndex, items):
                guard state.panes.indices.contains(paneIndex) else { return .none }
                state.panes[paneIndex].items = items
                state.panes[paneIndex].selectedIndex = min(state.panes[paneIndex].selectedIndex, max(0, items.count - 1))
                return .none

            case .delegate:
                return .none

            case .binding:
                return .none
            }
        }
    }

    // MARK: - Helpers

    // Provide instant, synchronous items for known providers so UI is never empty
    private func makeInitialItemsIfAvailable(providerID: String, query: String, context: PaletteContext) -> [CommandItem]? {
        switch providerID {
        case "slide.quicklinks":
            return initialQuickLinksItems(query: query)
        case "slide.websearch":
            return initialWebSearchItems(query: query, context: context)
        default:
            return nil
        }
    }

    // Minimal URL detection mirroring provider logic
    private func detectURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let u = URL(string: trimmed), u.scheme != nil { return u }
        if trimmed.contains(".") && !trimmed.contains(" ") {
            if let u = URL(string: "https://\(trimmed)") { return u }
        }
        let patterns = [
            "^[a-zA-Z0-9-]+\\.[a-zA-Z]{2,}(/.*)?$",
            "^www\\.[a-zA-Z0-9-]+\\.[a-zA-Z]{2,}(/.*)?$",
            "^localhost(:[0-9]+)?(/.*)?$",
            "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}(:[0-9]+)?(/.*)?$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: trimmed.utf16.count)
                if regex.firstMatch(in: trimmed, options: [], range: range) != nil {
                    if let u = URL(string: "https://\(trimmed)") { return u }
                }
            }
        }
        return nil
    }

    private func initialQuickLinksItems(query: String) -> [CommandItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
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
            ("GitHub", "https://github.com", "asset:GitHub"),
            ("Notion", "https://notion.so", "asset:Notion"),
            ("Linear", "https://linear.app", "asset:Linear"),
            ("Google Docs", "https://docs.google.com", "asset:GoogleDocs"),
            ("Google Sheets", "https://sheets.google.com", "asset:GoogleSheets"),
            ("Google Calendar", "https://calendar.google.com", "asset:GoogleCalendar"),
            ("X (Twitter)", "https://x.com", "asset:X"),
            ("Discord", "https://discord.com/app", "asset:Discord"),
            ("YouTube", "https://youtube.com", "asset:YouTube"),
            ("Spotify", "https://open.spotify.com", "asset:Spotify"),
            ("Hacker News", "https://news.ycombinator.com", "asset:YC")
        ]
        let filtered = links.filter { title, _, _ in q.isEmpty || title.localizedCaseInsensitiveContains(q) }
        for (title, url, icon) in filtered {
            items.append(CommandItem(
                id: "quicklink-\(title)",
                title: title,
                subtitle: url,
                icon: icon,
                transition: .effect(.openURL(url))
            ))
        }
        if !q.isEmpty {
            if let u = detectURL(q) {
                items.insert(CommandItem(
                    id: "goto-url",
                    title: "Go to \(u.host ?? u.absoluteString)",
                    subtitle: u.absoluteString,
                    icon: "arrow.right.circle",
                    transition: .effect(.openURL(u.absoluteString))
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
        return items
    }

    private func initialWebSearchItems(query: String, context: PaletteContext) -> [CommandItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var items: [CommandItem] = []
        guard !q.isEmpty else {
            // Default suggestions when empty
            return [
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
        }
        if let u = detectURL(q) {
            let goTo: CommandTransitionSpec = context.currentObjectID != nil
                ? .effect(.updateCurrentURL(u.absoluteString))
                : .effect(.openURL(u.absoluteString))
            items.append(CommandItem(
                id: "goto-url",
                title: "Go to \(u.host ?? u.absoluteString)",
                subtitle: u.absoluteString,
                icon: "arrow.right.circle",
                transition: goTo
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
        return items
    }

    private func makeTopItems(from defs: [CommandDefinition]) -> [CommandItem] {
        defs.map { def in
            CommandItem(
                id: def.id.rawValue,
                title: def.title,
                subtitle: nil,
                icon: def.icon,
                metadata: def.shortcut,  // Show shortcut as metadata
                transition: topLevelTransition(from: def.entry)
            )
        }
    }

    private func topLevelTransition(from entry: CommandEntrySpec) -> CommandTransitionSpec {
        switch entry {
        case .direct(let effect):
            return .effect(effect)
        case .withProvider(let title, let providerID):
            return .pushPane(CommandPaneSpec(title: title, kind: .list(providerID: providerID)))
        case .workflow(let title, let steps):
            if let first = steps.first {
                switch first {
                case .input(let spec, let actionKey):
                    return .pushPane(CommandPaneSpec(title: title, kind: .input(spec, actionKey: actionKey)))
                case .list(let providerID):
                    return .pushPane(CommandPaneSpec(title: title, kind: .list(providerID: providerID)))
                }
            } else {
                return .pushPane(CommandPaneSpec(title: title, kind: .list(providerID: nil)))
            }
        }
    }

    private func apply(transition: CommandTransitionSpec, state: inout State) -> EffectOf<Self> {
        switch transition {
        case .effect(let eff):
            return .concatenate(
                .send(.delegate(.effectTriggered(eff))),
                .send(.close)
            )

        case .pushStaticList(let title, let items):
            var pane = CommandPane(title: title, kind: .list(providerID: nil))
            pane.items = items
            pane.sourceItems = items
            state.panes.append(pane)
            return .none

        case .pushPane(let spec):
            let pane = CommandPane(title: spec.title, kind: spec.kind)
            state.panes.append(pane)
            // Clear search query when pushing a new pane (like viewing objects)
            state.query = ""
            let paneIndex = state.panes.indices.last!
            switch spec.kind {
            case .list(let providerID):
                if let providerID { return .send(.startProvider(paneIndex: paneIndex, providerID: providerID)) }
                return .none
            case .input(let inputSpec, _):
                // When pushing an input pane, pre-fill the query with initial value
                state.query = inputSpec.initial
                return .none
            }
        }
    }

    private func filter(items: [CommandItem], query: String) -> [CommandItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { $0.title.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false) }
    }
}

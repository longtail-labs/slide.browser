import CommandPaletteCore
import ComposableArchitecture
import Dependencies
import Foundation
import Sharing
@preconcurrency import SlideDatabase
import SwiftUI
import AppKit
import FirebaseServices

// MARK: - CLI Command (dispatched from socket server)

public enum CLICommand: Equatable, Sendable {
    case objectOpen(type: String, url: String?, content: String?, cwd: String?, projectId: UUID?)
    case objectFocus(id: UUID)
    case objectClose(id: UUID)
    case objectBadge(id: UUID, count: Int)
    case objectStart(id: UUID)
    case objectStop(id: UUID, badge: Int?)
    case objectAttention(id: UUID)
    case objectRename(id: UUID, title: String)
    case notify(title: String, body: String?, objectId: UUID?)
    case projectSelect(id: UUID)
}

// MARK: - Slide App Feature (Content Browser Root)

@Reducer
public struct SlideAppFeature {
    @ObservableState
    public struct State {
        @Shared(.appStorage("isDarkMode")) public var isDarkMode = false

        // Content browser (main feature — single screen)
        public var browser = ContentBrowserFeature.State()

        // SomaFM mini-player
        public var somaFM = SomaFMFeature.State()

        // Command palette overlay
        @Presents public var commandPalette: CommandPaletteFeature.State?
        // Settings sheet
        @Presents public var settings: SettingsFeature.State?

        // Ephemeral UI feedback
        public var toastMessage: String? = nil
        public var toastActionLabel: String? = nil
        public var toastHasAction: Bool = false
        public var toastActionType: ToastActionType?

        public enum ToastActionType: Equatable {
            case openDownloadsFolder
        }

        // Agent toast (bottom-right overlay)
        public var agentToastTitle: String? = nil
        public var agentToastBody: String? = nil
        public var agentToastObjectId: UUID? = nil

        public init() {}
    }

    public enum Action: Sendable {
        case browser(ContentBrowserFeature.Action)
        case somaFM(SomaFMFeature.Action)
        case commandPalette(PresentationAction<CommandPaletteFeature.Action>)
        case settings(PresentationAction<SettingsFeature.Action>)

        case toggleCommandBar
        case openCommandBarObjects
        case openCommandBarProjects
        case openCommandBarNewTab
        case openCommandBarForCurrentObject
        case openCommandPaletteWithItems([CommandItem], context: PaletteContext, scope: PaletteScope, title: String)
        case toggleDarkMode
        case openSettings(SettingsFeature.Section = .keys)

        // Browser helpers wired to top-level triggers (keyboard/menu)
        case closeCurrentObject
        case closeFocusedPanel
        case duplicateCurrentObject
        case copyCurrentUrl
        case saveSelectionToNote
        case goBack
        case goForward
        case reload
        case zoomIn
        case zoomOut
        case resetZoom

        // Filter bar
        case focusFilterBar

        // Object creation shortcuts
        case createNewNote
        case createNewTerminal

        // Updates
        case checkForUpdates

        // CLI / Agent commands
        case cliCommand(CLICommand)

        // UI feedback
        case showToast(String, actionLabel: String? = nil)
        case showToastWithAction(String, actionLabel: String, actionType: State.ToastActionType)
        case hideToast
        case toastActionTapped

        // Agent toast (bottom-right with Go To action)
        case agentToastReceived(title: String, body: String?, objectId: UUID?)
        case agentToastDismissed
        case agentToastGoTo
    }

    @Dependency(\.slideDatabase) var database
    @Dependency(\.slideCommandRegistry) var registry

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.browser, action: \.browser) {
            ContentBrowserFeature()
        }

        Scope(state: \.somaFM, action: \.somaFM) {
            SomaFMFeature()
        }

        Reduce { state, action in
            return self.reduceCore(state: &state, action: action)
        }
        .ifLet(\.$commandPalette, action: \.commandPalette) {
            CommandPaletteFeature()
        }
        .ifLet(\.$settings, action: \.settings) {
            SettingsFeature()
        }
    }

    private func reduceCore(state: inout State, action: Action) -> EffectOf<Self> {
        switch action {

        // MARK: - Browser actions

        case .browser(.copyObjectLink(let objectId)):
            if let obj = state.browser.objects.first(where: { $0.uuidValue == objectId }),
               let url = obj.url {
                return .concatenate(
                    .run { _ in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    },
                    .send(.showToast("Copied link"))
                )
            }
            return .none

        case .browser:
            return .none

        case .somaFM:
            return .none

        // MARK: - Command palette

        case .toggleCommandBar:
            if state.commandPalette == nil {
                var paletteState = CommandPaletteFeature.State()
                paletteState.context = buildPaletteContext(state: state)
                state.commandPalette = paletteState
                AnalyticsService.logCommandBarOpened(mode: "toggle")
                return .send(.commandPalette(.presented(.open(scope: .cmdK, preselect: nil))))
            } else {
                state.commandPalette = nil
            }
            return .none

        case .openCommandBarObjects:
            var context = buildPaletteContext(state: state)
            let allObjects = state.browser.objects.sorted {
                ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast)
            }
            let activeProjectId = state.browser.activeProjectId
            // Find project names for labeling
            let projectMap: [UUID: String] = Dictionary(
                uniqueKeysWithValues: state.browser.projects.map { ($0.uuidValue, "\($0.icon) \($0.name)") }
            )

            // Build item for a single object
            func makeItem(_ obj: TaskObject, showProject: Bool) -> CommandItem {
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
                let subtitle: String = {
                    if showProject, let pid = obj.projectId, let name = projectMap[pid] {
                        return name
                    }
                    return obj.url?.absoluteString ?? obj.content ?? ""
                }()
                let metadata = obj.lastAccessedAt.map { relativeTime(from: $0) }
                return CommandItem(
                    id: obj.uuid,
                    title: obj.displayTitle.isEmpty ? "Untitled" : obj.displayTitle,
                    subtitle: subtitle,
                    icon: icon,
                    metadata: metadata,
                    transition: .effect(.custom("object.select", payload: [
                        "id": obj.uuid,
                        "projectId": obj.projectId?.uuidString ?? ""
                    ]))
                )
            }

            // Scoped items (current project only)
            let scopedItems: [CommandItem]
            if let pid = activeProjectId {
                scopedItems = allObjects.filter { $0.projectId == pid }.map { makeItem($0, showProject: false) }
            } else {
                scopedItems = allObjects.map { makeItem($0, showProject: false) }
            }

            // All items (show project name in subtitle)
            let unscopedItems = allObjects.map { makeItem($0, showProject: true) }

            // Set scope context
            if let pid = activeProjectId,
               let project = state.browser.projects.first(where: { $0.uuidValue == pid }) {
                context.scopeProjectId = pid.uuidString
                context.scopeProjectName = "\(project.icon) \(project.name)"
            }

            // Build palette state directly to include unscopedItems
            var paletteState = CommandPaletteFeature.State()
            paletteState.context = context
            paletteState.isPresented = true
            paletteState.scope = .cmdP
            paletteState.unscopedItems = unscopedItems
            let root = CommandPane(title: "Commands", kind: .list(providerID: nil))
            var list = CommandPane(title: "Objects", kind: .list(providerID: nil))
            list.items = scopedItems
            list.sourceItems = scopedItems
            paletteState.panes = [root, list]
            paletteState.closeOnFirstEscape = true
            state.commandPalette = paletteState
            return .none

        case .openCommandBarProjects:
            let context = buildPaletteContext(state: state)
            let projects = state.browser.projects.sorted(by: { $0.sortOrder < $1.sortOrder })
            var items: [CommandItem] = []
            for project in projects {
                items.append(CommandItem(
                    id: "project-\(project.uuid)",
                    title: "\(project.icon) \(project.name)",
                    subtitle: project.uuid == scratchpadProjectUUID ? "Default project" : "Switch to project",
                    icon: "folder",
                    transition: .effect(.custom("project.select", payload: ["projectId": project.uuid]))
                ))
            }
            return .send(.openCommandPaletteWithItems(items, context: context, scope: .cmdK, title: "Projects"))

        case .openCommandBarNewTab:
            var paletteState = CommandPaletteFeature.State()
            paletteState.context = buildPaletteContext(state: state)
            state.commandPalette = paletteState
            return .send(.commandPalette(.presented(.openWithProvider(scope: .cmdT, title: "Quick Links", providerID: "slide.quicklinks"))))

        case .openCommandBarForCurrentObject:
            // Get current URL if available
            var initialQuery = ""
            if let selectedId = state.browser.selectedObjectId,
               let obj = state.browser.objects.first(where: { $0.uuidValue == selectedId }),
               let url = obj.url {
                initialQuery = url.absoluteString
            }
            var paletteState = CommandPaletteFeature.State()
            paletteState.context = buildPaletteContext(state: state)
            state.commandPalette = paletteState
            return .send(.commandPalette(.presented(.openWithProvider(scope: .cmdL, title: "Web Search", providerID: "slide.websearch", initialQuery: initialQuery))))

        case .toggleDarkMode:
            state.$isDarkMode.withLock { $0.toggle() }
            AnalyticsService.logDarkModeToggled(enabled: state.isDarkMode)
            return .none

        case .openSettings(let section):
            state.settings = SettingsFeature.State(selected: section)
            return .none

        case .commandPalette(.presented(.delegate(let delegateAction))):
            switch delegateAction {
            case .effectTriggered(let effect):
                return handlePaletteEffect(effect, state: &state)
            case .didClose:
                state.commandPalette = nil
                return .none
            }

        case .commandPalette(.dismiss):
            state.commandPalette = nil
            return .none

        case .settings(.presented(.dismiss)):
            state.settings = nil
            return .none

        case .commandPalette:
            return .none

        case .settings:
            return .none

        // MARK: - Browser helpers

        case .closeCurrentObject:
            // Delete the focused object and close it (same as the x button)
            if let selectedId = state.browser.selectedObjectId {
                return .send(.browser(.deleteObject(selectedId)))
            }
            return .none

        case .closeFocusedPanel:
            // Close the panel but keep the object (x key)
            if !state.browser.visiblePanelIds.isEmpty {
                return .send(.browser(.closeFocusedPanel))
            }
            return .none

        case .duplicateCurrentObject:
            // For links, create a copy
            if let selectedId = state.browser.selectedObjectId,
               let obj = state.browser.objects.first(where: { $0.uuidValue == selectedId }),
               obj.kind == .link, let url = obj.url {
                return .send(.browser(.addLinkObject(obj.title ?? "Untitled", url)))
            }
            return .none

        case .copyCurrentUrl:
            if let selId = state.browser.selectedObjectId,
               let obj = state.browser.objects.first(where: { $0.uuidValue == selId }),
               let url = obj.url {
                return .concatenate(
                    .run { _ in
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    },
                    .send(.showToast("Copied URL"))
                )
            }
            return .none

        case .saveSelectionToNote:
            if let selectedId = state.browser.selectedObjectId,
               let obj = state.browser.objects.first(where: { $0.uuidValue == selectedId }) {
                if obj.kind == .link {
                    return .run { _ in
                        NotificationCenter.default.post(
                            name: Notification.Name("TriggerSaveSelection"),
                            object: nil,
                            userInfo: [WebFindKeys.objectId: selectedId]
                        )
                    }
                } else if obj.kind == .pdf {
                    return .run { _ in
                        NotificationCenter.default.post(
                            name: Notification.Name("TriggerSaveSelectionPDF"),
                            object: nil
                        )
                    }
                }
            }
            return .none

        case .goBack: return .send(.browser(.goBack))
        case .goForward: return .send(.browser(.goForward))
        case .reload: return .send(.browser(.reload))
        case .zoomIn: return .send(.browser(.zoomIn))
        case .zoomOut: return .send(.browser(.zoomOut))
        case .resetZoom: return .send(.browser(.resetZoom))

        case .focusFilterBar:
            return .run { _ in
                NotificationCenter.default.post(name: .focusFilterBar, object: nil)
            }

        case .createNewNote:
            #if DEBUG
            print("[KeyboardShortcut] Reducer received createNewNote")
            #endif
            return .send(.browser(.addNoteObject("Untitled Note", "")))

        case .createNewTerminal:
            return .send(.browser(.addTerminalObject("Terminal", "~")))

        case .checkForUpdates:
            return .run { send in
                let checker = ConveyorUpdateChecker.shared
                if checker.checkForUpdates() {
                    AnalyticsService.logEvent("update_check_triggered", parameters: ["source": "menu"])
                } else {
                    await send(.showToast("Updates are only available in the packaged app"))
                }
            }

        // MARK: - CLI Commands

        case .cliCommand(let cmd):
            switch cmd {
            case .objectOpen(let type, let url, let content, let cwd, let projectId):
                switch type {
                case "browser", "link":
                    if let urlStr = url, let linkURL = URL(string: urlStr) {
                        let title = linkURL.host ?? "New Tab"
                        if let pid = projectId {
                            return .concatenate(
                                .send(.browser(.selectProject(pid))),
                                .send(.browser(.addLinkObject(title, linkURL)))
                            )
                        }
                        return .send(.browser(.addLinkObject(title, linkURL)))
                    }
                case "note":
                    let title = "Note"
                    let body = content ?? ""
                    return .send(.browser(.addNoteObject(title, body)))
                case "terminal":
                    let dir = cwd ?? "~"
                    return .send(.browser(.addTerminalObject("Terminal", dir)))
                case "code-editor":
                    let filePath = url
                    let title: String
                    if let fp = filePath {
                        title = (fp as NSString).lastPathComponent
                    } else {
                        title = "Code Editor"
                    }
                    let lang: String
                    if let fp = filePath {
                        let ext = (fp as NSString).pathExtension
                        lang = ext.isEmpty ? "plain" : ext
                    } else {
                        lang = "plain"
                    }
                    return .send(.browser(.addCodeEditorObject(title, filePath, lang, content)))
                default:
                    break
                }
                return .none

            case .objectFocus(let id):
                return .send(.browser(.selectObjectId(id)))

            case .objectClose(let id):
                return .send(.browser(.deleteObject(id)))

            case .objectBadge(let id, let count):
                return .send(.browser(.setBadgeCount(id, count)))

            case .objectStart(let id):
                return .send(.browser(.setActivityState(id, .active)))

            case .objectStop(let id, let badge):
                var effects: [EffectOf<Self>] = [
                    .send(.browser(.setActivityState(id, .idle)))
                ]
                if let badge, badge > 0 {
                    effects.append(.send(.browser(.setBadgeCount(id, badge))))
                }
                return .concatenate(effects)

            case .objectAttention(let id):
                return .send(.browser(.setActivityState(id, .attention)))

            case .objectRename(let id, let title):
                return .send(.browser(.renameObject(id, title)))

            case .notify(let title, let body, let objectId):
                return .send(.agentToastReceived(title: title, body: body, objectId: objectId))

            case .projectSelect(let id):
                return .send(.browser(.selectProject(id)))
            }

        // MARK: - Agent Toast

        case let .agentToastReceived(title, body, objectId):
            state.agentToastTitle = title
            state.agentToastBody = body
            state.agentToastObjectId = objectId
            return .run { send in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await send(.agentToastDismissed)
            }

        case .agentToastDismissed:
            state.agentToastTitle = nil
            state.agentToastBody = nil
            state.agentToastObjectId = nil
            return .none

        case .agentToastGoTo:
            let objectId = state.agentToastObjectId
            state.agentToastTitle = nil
            state.agentToastBody = nil
            state.agentToastObjectId = nil
            if let id = objectId {
                return .send(.browser(.selectObjectId(id)))
            }
            return .none

        // MARK: - Toast

        case let .showToast(message, actionLabel):
            state.toastMessage = message
            state.toastActionLabel = actionLabel
            state.toastHasAction = actionLabel != nil
            return .run { send in
                let duration: UInt64 = actionLabel != nil ? 3_000_000_000 : 1_500_000_000
                try? await Task.sleep(nanoseconds: duration)
                await send(.hideToast)
            }

        case let .showToastWithAction(message, actionLabel, actionType):
            state.toastMessage = message
            state.toastActionLabel = actionLabel
            state.toastHasAction = true
            state.toastActionType = actionType
            return .run { send in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await send(.hideToast)
            }

        case .hideToast:
            state.toastMessage = nil
            state.toastActionLabel = nil
            state.toastHasAction = false
            state.toastActionType = nil
            return .none

        case .toastActionTapped:
            let actionType = state.toastActionType
            state.toastMessage = nil
            state.toastActionLabel = nil
            state.toastHasAction = false
            state.toastActionType = nil
            switch actionType {
            case .openDownloadsFolder:
                return .run { _ in
                    if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                        NSWorkspace.shared.open(downloads)
                    }
                }
            case .none:
                return .none
            }

        case let .openCommandPaletteWithItems(items, context, scope, title):
            var paletteState = CommandPaletteFeature.State()
            paletteState.context = context
            paletteState.isPresented = true
            paletteState.scope = scope
            let root = CommandPane(title: "Commands", kind: .list(providerID: nil))
            var list = CommandPane(title: title, kind: .list(providerID: nil))
            list.items = items
            list.sourceItems = items
            paletteState.panes = [root, list]
            paletteState.closeOnFirstEscape = true
            state.commandPalette = paletteState
            return .none
        }
    }

    // MARK: - Command Palette Helpers

    private func buildPaletteContext(state: State) -> PaletteContext {
        var context = PaletteContext()
        context.route = "browser"
        if let selectedId = state.browser.selectedObjectId {
            context.currentObjectID = selectedId.uuidString
        }
        context.selectionIDs = state.browser.objects.map { $0.uuid }
        return context
    }

    private func relativeTime(from date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }

    private func handlePaletteEffect(_ effect: CommandEffect, state: inout State) -> EffectOf<Self> {
        switch effect {
        case .openURL(let url):
            if let linkURL = URL(string: url) {
                let title = linkURL.host ?? "New Tab"
                return .send(.browser(.addLinkObject(title, linkURL)))
            }
            return .none

        case .updateCurrentURL(let url):
            if let selectedId = state.browser.selectedObjectId,
               let objIndex = state.browser.objects.firstIndex(where: { $0.uuidValue == selectedId }),
               let linkURL = URL(string: url) {
                var obj = state.browser.objects[objIndex]
                if obj.kind == .link {
                    let oldUrl = obj.url
                    obj.url = linkURL
                    if let existingUrl = oldUrl, existingUrl.host != linkURL.host {
                        obj.title = linkURL.host ?? obj.title ?? "Link"
                    }
                    return .concatenate(
                        .run { _ in
                            NotificationCenter.default.post(
                                name: .webNavigateToURL,
                                object: nil,
                                userInfo: [
                                    WebFindKeys.objectId: selectedId,
                                    "url": linkURL
                                ]
                            )
                        },
                        .send(.browser(.updateObject(obj)))
                    )
                } else {
                    return handlePaletteEffect(.openURL(url), state: &state)
                }
            } else {
                return handlePaletteEffect(.openURL(url), state: &state)
            }

        case .selectTask:
            // No longer applicable
            return .none

        case .openTask:
            // No longer applicable
            return .none

        case .showSettings:
            return .send(.openSettings(.keys))

        case .toggleDarkMode:
            return .send(.toggleDarkMode)

        case .custom(let actionKey, let payload):
            switch actionKey {
            // Object actions
            case "object.select":
                if let objectId = payload["id"],
                   let uuid = UUID(uuidString: objectId) {
                    // If the object belongs to a different project, switch to it
                    if let projectIdStr = payload["projectId"],
                       !projectIdStr.isEmpty,
                       let projectUUID = UUID(uuidString: projectIdStr),
                       state.browser.activeProjectId != projectUUID {
                        return .concatenate(
                            .send(.browser(.selectProject(projectUUID))),
                            .send(.browser(.selectObjectId(uuid)))
                        )
                    }
                    return .send(.browser(.selectObjectId(uuid)))
                }
            case "object.copy-link":
                if let objectId = payload["id"],
                   let uuid = UUID(uuidString: objectId),
                   let obj = state.browser.objects.first(where: { $0.uuidValue == uuid }),
                   let url = obj.url {
                    return .concatenate(
                        .run { _ in
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        },
                        .send(.showToast("Copied link"))
                    )
                }
            case "object.delete":
                if let objectId = payload["id"], let uuid = UUID(uuidString: objectId) {
                    return .send(.browser(.deleteObject(uuid)))
                }

            // Browser actions
            case "browser.close-object":
                return .send(.closeCurrentObject)
            case "browser.duplicate-object":
                return .send(.duplicateCurrentObject)
            case "browser.copy-url":
                return .send(.copyCurrentUrl)
            case "browser.go-back":
                return .send(.goBack)
            case "browser.go-forward":
                return .send(.goForward)
            case "browser.reload":
                return .send(.reload)
            case "browser.toggle-fullscreen":
                return .send(.browser(.toggleFullscreen))
            case "browser.toggle-sidebar":
                return .send(.browser(.toggleSidebar))
            case "browser.find-on-page":
                return .send(.browser(.showFindBar))
            case "object.rename":
                if let selectedId = state.browser.selectedObjectId {
                    return .run { _ in
                        NotificationCenter.default.post(
                            name: Notification.Name("TriggerInlineRename"),
                            object: nil,
                            userInfo: ["objectId": selectedId]
                        )
                    }
                }
            case "object.open-split":
                if let selectedId = state.browser.selectedObjectId {
                    return .send(.browser(.openInNewPanel(selectedId)))
                }

            // Project actions
            case "project.assign":
                if let objectId = payload["objectId"], let projectId = payload["projectId"],
                   let objUUID = UUID(uuidString: objectId) {
                    let projUUID = projectId.isEmpty ? nil : UUID(uuidString: projectId)
                    return .send(.browser(.moveObjectToProject(objUUID, projUUID)))
                }
            case "project.select":
                if let projectId = payload["projectId"] {
                    let uuid = UUID(uuidString: projectId)
                    return .send(.browser(.selectProject(uuid)))
                }
            case "project.create-and-assign":
                let objectId = payload["objectId"].flatMap { UUID(uuidString: $0) }
                let name = payload["name"] ?? "Untitled"
                return .run { send in
                    let project = try await database.createProject(name, "📁", "#6B7280")
                    if let objId = objectId {
                        try? await database.assignObjectToProject(objId, project.uuidValue)
                    }
                }

            // Create
            case "create.project":
                NotificationCenter.default.post(name: Notification.Name("ShowCreateProject"), object: nil)
                return .none
            case "create.note":
                return .send(.createNewNote)
            case "create.terminal":
                return .send(.createNewTerminal)

            default:
                print("[App] Unhandled custom action: \(actionKey)")
            }
            return .none
        }
    }
}

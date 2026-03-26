import ComposableArchitecture
import Dependencies
import Foundation
import Sharing
@preconcurrency import SlideDatabase
import SwiftUI

// MARK: - Content Browser Feature (replaces Tasks + Workspace)

@Reducer
public struct ContentBrowserFeature {
    @ObservableState
    public struct State: Equatable {
        // All objects (flat list)
        public var objects: [TaskObject] = []
        public var projects: [OBXProject] = []
        @Shared(.appStorage("activeProjectId")) public var persistedProjectId = ""
        public var activeProjectId: UUID? = nil   // nil until projects load; always set to a project
        public var searchQuery: String = ""
        @Shared(.appStorage("isSidebarVisible")) public var isSidebarVisible = true

        // Panel state (replaces single selectedObjectId)
        public var visiblePanelIds: [UUID] = []
        public var focusedPanelIndex: Int = 0

        // Backward-compatible computed property
        public var selectedObjectId: UUID? {
            guard !visiblePanelIds.isEmpty,
                  focusedPanelIndex >= 0,
                  focusedPanelIndex < visiblePanelIds.count else { return nil }
            return visiblePanelIds[focusedPanelIndex]
        }

        // Persisted panel IDs
        @Shared(.appStorage("visiblePanelIds")) public var persistedPanelIds = ""

        // UI flags
        public var isFullscreen: Bool = false
        public var isFindBarVisible: Bool = false
        public var findQuery: String = ""
        public var isLoading: Bool = false
        // Track objects being deleted to prevent observer from re-adding them
        public var pendingDeletions: Set<UUID> = []

        // Agent activity state (transient — not persisted, resets to .idle on launch)
        public var activityStates: [UUID: ObjectActivityState] = [:]
        // Badge counts per object (transient)
        public var badgeCounts: [UUID: Int] = [:]

        // Sidebar sort mode
        @Shared(.appStorage("sidebarSort")) public var sidebarSortRaw = "newest"

        public var sidebarSort: SidebarSortMode {
            SidebarSortMode(rawValue: sidebarSortRaw) ?? .newest
        }

        // Filtered objects based on current filters
        public var filteredObjects: [TaskObject] {
            var result = objects
            // Filter by project
            if let projectId = activeProjectId {
                result = result.filter { $0.projectId == projectId }
            }
            // Filter by search query
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                result = result.filter { obj in
                    let title = obj.displayTitle.lowercased()
                    let url = obj.url?.absoluteString.lowercased() ?? ""
                    let content = (obj.content ?? "").lowercased()
                    return title.contains(q) || url.contains(q) || content.contains(q)
                }
            }
            // Apply sort
            switch sidebarSort {
            case .lastOpened:
                result.sort { ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast) }
            case .newest:
                result.sort { $0.createdAt > $1.createdAt }
            case .oldest:
                result.sort { $0.createdAt < $1.createdAt }
            case .manual:
                break // keep sortOrder from DB
            }
            return result
        }

        public var selectedObject: TaskObject? {
            guard let id = selectedObjectId else { return nil }
            return objects.first(where: { $0.uuidValue == id })
        }

        /// Number of currently visible panels
        public var panelCount: Int { visiblePanelIds.count }

        public init() {}
    }

    public enum Action: Sendable {
        // Lifecycle
        case onAppear
        case onDisappear

        // Data loading
        case objectsLoaded([TaskObject])
        case projectsLoaded([OBXProject])
        case deletionCompleted(UUID)

        // Selection
        case selectObjectId(UUID?)
        case selectNextObject
        case selectPreviousObject

        // Panel management
        case openInNewPanel(UUID)
        case closePanel(Int)
        case closeFocusedPanel
        case focusPanel(Int)
        case focusPanelLeft
        case focusPanelRight
        case replaceFocusedPanel(UUID)

        // Filtering
        case setSearchQuery(String)
        case submitSearchQuery

        // Project filtering
        case selectProject(UUID?)

        // Project CRUD
        case createProject(String, String, String)
        case deleteProject(UUID)
        case updateProject(OBXProject)
        case reorderProjects([UUID])
        case moveObjectToProject(UUID, UUID?)

        // Object CRUD
        case addLinkObject(String, URL)
        case addLinkObjectBackground(String, URL)
        case addPDFObject(String, URL)
        case addImageObject(String, URL)
        case addVideoObject(String, URL)
        case addAudioObject(String, URL)
        case addNoteObject(String, String)
        case addTerminalObject(String, String)
        case addCodeEditorObject(String, String?, String, String?)
        case objectAdded(TaskObject)
        case updateObject(TaskObject)
        case deleteObject(UUID)
        case duplicateObject(UUID)
        case renameObject(UUID, String)
        case autoRenameObject(UUID, String)
        case resetCustomName(UUID)
        case reorderObjects([UUID])

        // Sort
        case setSidebarSort(SidebarSortMode)

        // UI controls
        case toggleSidebar
        case toggleFullscreen
        case showFindBar
        case hideFindBar
        case setFindQuery(String)
        case findNext
        case findPrevious

        // Web controls (forwarded via notifications)
        case goBack
        case goForward
        case reload
        case zoomIn
        case zoomOut
        case resetZoom

        // Agent activity & badges
        case setActivityState(UUID, ObjectActivityState)
        case setBadgeCount(UUID, Int)
        case clearBadge(UUID)

        // Open/access tracking
        case copyObjectLink(UUID)
    }

    @Dependency(\.slideDatabase) var database

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                // Restore saved panels from persisted storage
                let raw = state.persistedPanelIds
                if !raw.isEmpty {
                    let restored = raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
                    if !restored.isEmpty {
                        state.visiblePanelIds = restored
                        state.focusedPanelIndex = min(state.focusedPanelIndex, max(restored.count - 1, 0))
                    }
                }
                // Restore persisted project (default to scratchpad)
                let savedProjectId = state.persistedProjectId
                if !savedProjectId.isEmpty, let uuid = UUID(uuidString: savedProjectId) {
                    state.activeProjectId = uuid
                } else if let spUUID = UUID(uuidString: scratchpadProjectUUID) {
                    state.activeProjectId = spUUID
                }
                return .merge(
                    // Ensure Scratchpad exists
                    .run { _ in
                        try? await database.ensureScratchpadExists()
                    },
                    // Load initial objects
                    .run { send in
                        let objects = try await database.fetchAllObjects()
                        await send(.objectsLoaded(objects))
                    },
                    // Load projects
                    .run { send in
                        let projects = try await database.fetchAllProjects()
                        await send(.projectsLoaded(projects))
                    },
                    // Subscribe to object changes
                    .run { send in
                        for await objects in database.objectsStream() {
                            await send(.objectsLoaded(objects))
                        }
                    }.cancellable(id: CancelID.objectsStream, cancelInFlight: true),
                    // Subscribe to project changes
                    .run { send in
                        for await projects in database.projectsStream() {
                            await send(.projectsLoaded(projects))
                        }
                    }.cancellable(id: CancelID.projectsStream, cancelInFlight: true)
                )

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.objectsStream),
                    .cancel(id: CancelID.projectsStream)
                )

            case .objectsLoaded(let objects):
                // Filter out objects that are still pending deletion to prevent
                // the database observer from re-adding them before the delete commits
                if state.pendingDeletions.isEmpty {
                    state.objects = objects
                } else {
                    state.objects = objects.filter { !state.pendingDeletions.contains($0.uuidValue) }
                }
                state.isLoading = false
                // Prune panels whose objects were deleted
                let objectIds = Set(state.objects.map { $0.uuidValue })
                state.visiblePanelIds.removeAll { !objectIds.contains($0) }
                // Clamp focused index
                if state.visiblePanelIds.isEmpty {
                    state.focusedPanelIndex = 0
                } else {
                    state.focusedPanelIndex = min(state.focusedPanelIndex, state.visiblePanelIds.count - 1)
                }
                return .none

            case .deletionCompleted(let id):
                state.pendingDeletions.remove(id)
                return .none

            case .projectsLoaded(let projects):
                state.projects = projects
                return .none

            // MARK: - Selection

            case .selectObjectId(let id):
                guard let id = id else {
                    state.visiblePanelIds = []
                    state.focusedPanelIndex = 0
                    savePanelsEffect(&state)
                    return .none
                }
                // Single panel for all objects
                state.visiblePanelIds = [id]
                state.focusedPanelIndex = 0
                // Auto-clear badge and activity when user focuses an object
                state.badgeCounts[id] = nil
                state.activityStates[id] = nil
                savePanelsEffect(&state)
                return .run { _ in
                    try? await database.updateObjectAccess(id)
                }

            case .selectNextObject:
                let filtered = state.filteredObjects
                guard !filtered.isEmpty else { return .none }
                if let currentId = state.selectedObjectId,
                   let idx = filtered.firstIndex(where: { $0.uuidValue == currentId }) {
                    let nextIdx = min(idx + 1, filtered.count - 1)
                    return .send(.selectObjectId(filtered[nextIdx].uuidValue))
                } else {
                    return .send(.selectObjectId(filtered.first?.uuidValue))
                }

            case .selectPreviousObject:
                let filtered = state.filteredObjects
                guard !filtered.isEmpty else { return .none }
                if let currentId = state.selectedObjectId,
                   let idx = filtered.firstIndex(where: { $0.uuidValue == currentId }) {
                    let prevIdx = max(idx - 1, 0)
                    return .send(.selectObjectId(filtered[prevIdx].uuidValue))
                } else {
                    return .send(.selectObjectId(filtered.last?.uuidValue))
                }

            // MARK: - Panel Management

            case .openInNewPanel(let objectId):
                // Cmd+click: add to split view
                if state.visiblePanelIds.contains(objectId) {
                    // Already showing — focus it
                    if let idx = state.visiblePanelIds.firstIndex(of: objectId) {
                        state.focusedPanelIndex = idx
                    }
                } else {
                    state.visiblePanelIds.append(objectId)
                    state.focusedPanelIndex = state.visiblePanelIds.count - 1
                }
                savePanelsEffect(&state)
                return .run { _ in
                    try? await database.updateObjectAccess(objectId)
                }

            case .closePanel(let index):
                guard index >= 0, index < state.visiblePanelIds.count else { return .none }
                let wasFocusedIndex = state.focusedPanelIndex
                state.visiblePanelIds.remove(at: index)
                if state.visiblePanelIds.isEmpty {
                    state.focusedPanelIndex = 0
                } else if wasFocusedIndex > index {
                    state.focusedPanelIndex = wasFocusedIndex - 1
                } else if wasFocusedIndex == index {
                    state.focusedPanelIndex = max(0, index - 1)
                } else {
                    state.focusedPanelIndex = min(wasFocusedIndex, state.visiblePanelIds.count - 1)
                }
                savePanelsEffect(&state)
                return .none

            case .closeFocusedPanel:
                guard !state.visiblePanelIds.isEmpty else { return .none }
                return .send(.closePanel(state.focusedPanelIndex))

            case .focusPanel(let index):
                guard index >= 0, index < state.visiblePanelIds.count else { return .none }
                state.focusedPanelIndex = index
                return .none

            case .focusPanelLeft:
                if state.focusedPanelIndex > 0 { state.focusedPanelIndex -= 1 }
                return .none

            case .focusPanelRight:
                if state.focusedPanelIndex < state.visiblePanelIds.count - 1 { state.focusedPanelIndex += 1 }
                return .none

            case .replaceFocusedPanel(let objectId):
                if let existingIdx = state.visiblePanelIds.firstIndex(of: objectId) {
                    state.focusedPanelIndex = existingIdx
                    return .none
                }
                if state.visiblePanelIds.isEmpty {
                    state.visiblePanelIds = [objectId]
                    state.focusedPanelIndex = 0
                } else {
                    state.visiblePanelIds[state.focusedPanelIndex] = objectId
                }
                savePanelsEffect(&state)
                return .run { _ in try? await database.updateObjectAccess(objectId) }

            // MARK: - Filtering

            case .setSearchQuery(let query):
                state.searchQuery = query
                return .none

            case .submitSearchQuery:
                switch SlideQuickInputParser.action(for: state.searchQuery) {
                case .filter:
                    return .none

                case .openURL(let url):
                    state.searchQuery = ""
                    let title = url.host ?? "New Tab"
                    return .send(.addLinkObject(title, url))

                case .createNote(let title, let content):
                    state.searchQuery = ""
                    return .send(.addNoteObject(title, content))

                case .createTerminal(let title, let workingDirectory):
                    state.searchQuery = ""
                    return .send(.addTerminalObject(title, workingDirectory))
                }

            case .selectProject(let projectId):
                state.activeProjectId = projectId
                state.$persistedProjectId.withLock { $0 = projectId?.uuidString ?? "" }
                return .none

            // MARK: - Project CRUD

            case .createProject(let name, let icon, let colorHex):
                return .run { send in
                    let project = try await database.createProject(name, icon, colorHex)
                    await send(.selectProject(project.uuidValue))
                }

            case .deleteProject(let id):
                // Don't allow deleting Scratchpad
                guard id.uuidString != scratchpadProjectUUID else { return .none }
                if state.activeProjectId == id {
                    // Fall back to Scratchpad
                    let spUUID = UUID(uuidString: scratchpadProjectUUID)
                    state.activeProjectId = spUUID
                    state.$persistedProjectId.withLock { $0 = spUUID?.uuidString ?? "" }
                }
                return .run { _ in
                    try? await database.deleteProject(id)
                }

            case .updateProject(let project):
                return .run { _ in
                    try? await database.updateProject(project)
                }

            case .reorderProjects(let orderedIds):
                return .run { _ in
                    try? await database.reorderProjects(orderedIds)
                }

            case .moveObjectToProject(let objectId, let projectId):
                return .run { _ in
                    try? await database.assignObjectToProject(objectId, projectId)
                }

            // MARK: - Object CRUD

            case .addLinkObject(let title, let url):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createLinkObject(title, url, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.selectObjectId(obj.uuidValue))
                }

            case .addLinkObjectBackground(let title, let url):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createLinkObject(title, url, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.openInNewPanel(obj.uuidValue))
                }

            case .addPDFObject(let title, let sourceFile):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createPDFObject(title, sourceFile, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.selectObjectId(obj.uuidValue))
                }

            case .addImageObject(let title, let sourceFile):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createImageObject(title, sourceFile, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.selectObjectId(obj.uuidValue))
                }

            case .addVideoObject(let title, let sourceFile):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createVideoObject(title, sourceFile, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.selectObjectId(obj.uuidValue))
                }

            case .addAudioObject(let title, let sourceFile):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createAudioObject(title, sourceFile, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.selectObjectId(obj.uuidValue))
                }

            case .addNoteObject(let title, let content):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createNoteObject(title, content, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.selectObjectId(obj.uuidValue))
                }

            case .addTerminalObject(let title, let workingDirectory):
                let currentProjectId = state.activeProjectId
                return .run { send in
                    let obj = try await database.createTerminalObject(title, workingDirectory, currentProjectId)
                    await send(.objectAdded(obj))
                    await send(.selectObjectId(obj.uuidValue))
                }

            case let .addCodeEditorObject(title, filePath, language, content):
                let obj = OBXObject.createCodeEditor(title: title, filePath: filePath, language: language, content: content)
                if let projectId = state.activeProjectId,
                   let project = state.projects.first(where: { $0.uuidValue == projectId }) {
                    obj.project.target = project
                }
                state.objects.append(obj)
                state.visiblePanelIds = [obj.uuidValue]
                state.focusedPanelIndex = 0
                savePanelsEffect(&state)
                return .run { [obj] _ in
                    try? await database.updateObject(obj)
                }

            case .objectAdded(let obj):
                if !state.objects.contains(where: { $0.uuidValue == obj.uuidValue }) {
                    state.objects.append(obj)
                }
                return .none

            case .updateObject(let object):
                // Skip updates for objects pending deletion — the WebView may still
                // fire metadata callbacks before the registry cleans it up
                guard !state.pendingDeletions.contains(object.uuidValue),
                      let idx = state.objects.firstIndex(where: { $0.uuidValue == object.uuidValue })
                else { return .none }
                state.objects[idx] = object
                return .run { _ in
                    try? await database.updateObject(object)
                }

            case .deleteObject(let id):
                state.pendingDeletions.insert(id)
                state.objects.removeAll { $0.uuidValue == id }
                // Remove from panels if present
                state.visiblePanelIds.removeAll { $0 == id }
                // Clamp focused index
                if state.visiblePanelIds.isEmpty {
                    state.focusedPanelIndex = 0
                    // Auto-select most recently accessed object
                    let nextObject = state.filteredObjects
                        .sorted { ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast) }
                        .first
                    if let next = nextObject {
                        state.visiblePanelIds = [next.uuidValue]
                        savePanelsEffect(&state)
                    }
                } else {
                    state.focusedPanelIndex = max(0, min(state.focusedPanelIndex, state.visiblePanelIds.count - 1))
                }
                return .run { send in
                    try? await database.deleteObject(id)
                    await send(.deletionCompleted(id))
                }

            case .duplicateObject(let id):
                guard let obj = state.objects.first(where: { $0.uuidValue == id }) else { return .none }
                let title = obj.title ?? "Untitled"
                switch obj.kind {
                case .link:
                    if let url = obj.url {
                        return .send(.addLinkObject(title, url))
                    }
                case .note:
                    return .send(.addNoteObject(title, obj.content ?? ""))
                default:
                    break
                }
                return .none

            case .renameObject(let id, let newTitle):
                // User-initiated rename → sets customName (sticky)
                if let idx = state.objects.firstIndex(where: { $0.uuidValue == id }) {
                    guard state.objects[idx].customName != newTitle else { return .none }
                    state.objects[idx].customName = newTitle
                    state.objects[idx].displayName = newTitle
                    let obj = state.objects[idx]
                    return .run { _ in
                        try? await database.updateObject(obj)
                    }
                }
                return .none

            case .autoRenameObject(let id, let newTitle):
                // System-initiated rename (OSC/webview) → only updates if no customName
                if let idx = state.objects.firstIndex(where: { $0.uuidValue == id }) {
                    guard state.objects[idx].customName.isEmpty else { return .none }
                    guard state.objects[idx].title != newTitle else { return .none }
                    state.objects[idx].title = newTitle
                    let obj = state.objects[idx]
                    return .run { _ in
                        try? await database.updateObject(obj)
                    }
                }
                return .none

            case .resetCustomName(let id):
                if let idx = state.objects.firstIndex(where: { $0.uuidValue == id }) {
                    state.objects[idx].customName = ""
                    let obj = state.objects[idx]
                    return .run { _ in
                        try? await database.updateObject(obj)
                    }
                }
                return .none

            case .reorderObjects(let orderedIds):
                var reordered: [TaskObject] = []
                for id in orderedIds {
                    if let obj = state.objects.first(where: { $0.uuidValue == id }) {
                        reordered.append(obj)
                    }
                }
                for obj in state.objects where !orderedIds.contains(obj.uuidValue) {
                    reordered.append(obj)
                }
                state.objects = reordered
                return .run { _ in
                    try? await database.reorderObjects(orderedIds)
                }

            // MARK: - Agent Activity & Badges

            case .setActivityState(let objectId, let activityState):
                state.activityStates[objectId] = activityState == .idle ? nil : activityState
                return .none

            case .setBadgeCount(let objectId, let count):
                state.badgeCounts[objectId] = count > 0 ? count : nil
                return .none

            case .clearBadge(let objectId):
                state.badgeCounts[objectId] = nil
                state.activityStates[objectId] = nil
                return .none

            // MARK: - Sort

            case .setSidebarSort(let mode):
                state.$sidebarSortRaw.withLock { $0 = mode.rawValue }
                return .none

            // MARK: - UI Controls

            case .toggleSidebar:
                state.$isSidebarVisible.withLock { $0.toggle() }
                return .none

            case .toggleFullscreen:
                state.isFullscreen.toggle()
                return .none

            case .showFindBar:
                state.isFindBarVisible = true
                return .none

            case .hideFindBar:
                state.isFindBarVisible = false
                state.findQuery = ""
                return .none

            case .setFindQuery(let query):
                state.findQuery = query
                guard let selectedId = state.selectedObjectId else { return .none }
                return .run { _ in
                    NotificationCenter.default.post(
                        name: .webFindNext,
                        object: nil,
                        userInfo: [WebFindKeys.objectId: selectedId, WebFindKeys.query: query]
                    )
                }

            case .findNext:
                guard let selectedId = state.selectedObjectId else { return .none }
                let query = state.findQuery
                return .run { _ in
                    NotificationCenter.default.post(
                        name: .webFindNext,
                        object: nil,
                        userInfo: [WebFindKeys.objectId: selectedId, WebFindKeys.query: query]
                    )
                }

            case .findPrevious:
                guard let selectedId = state.selectedObjectId else { return .none }
                let query = state.findQuery
                return .run { _ in
                    NotificationCenter.default.post(
                        name: .webFindPrevious,
                        object: nil,
                        userInfo: [WebFindKeys.objectId: selectedId, WebFindKeys.query: query]
                    )
                }

            // MARK: - Web Controls

            case .goBack:
                guard let selectedId = state.selectedObjectId else { return .none }
                return .run { _ in
                    NotificationCenter.default.post(name: .webGoBack, object: nil, userInfo: [WebFindKeys.objectId: selectedId])
                }

            case .goForward:
                guard let selectedId = state.selectedObjectId else { return .none }
                return .run { _ in
                    NotificationCenter.default.post(name: .webGoForward, object: nil, userInfo: [WebFindKeys.objectId: selectedId])
                }

            case .reload:
                guard let selectedId = state.selectedObjectId else { return .none }
                return .run { _ in
                    NotificationCenter.default.post(name: .webReload, object: nil, userInfo: [WebFindKeys.objectId: selectedId])
                }

            case .zoomIn:
                guard let selectedId = state.selectedObjectId else { return .none }
                return .run { _ in
                    NotificationCenter.default.post(name: .webZoomIn, object: nil, userInfo: [WebFindKeys.objectId: selectedId])
                }

            case .zoomOut:
                guard let selectedId = state.selectedObjectId else { return .none }
                return .run { _ in
                    NotificationCenter.default.post(name: .webZoomOut, object: nil, userInfo: [WebFindKeys.objectId: selectedId])
                }

            case .resetZoom:
                guard let selectedId = state.selectedObjectId else { return .none }
                return .run { _ in
                    NotificationCenter.default.post(name: .webResetZoom, object: nil, userInfo: [WebFindKeys.objectId: selectedId])
                }

            case .copyObjectLink(let objectId):
                return .none // Handled by parent
            }
        }
    }

    private enum CancelID {
        case objectsStream
        case projectsStream
    }

    /// Persist current panel IDs to @Shared storage
    private func savePanelsEffect(_ state: inout State) {
        let encoded = state.visiblePanelIds.map { $0.uuidString }.joined(separator: ",")
        state.$persistedPanelIds.withLock { $0 = encoded }
    }
}

// MARK: - Sidebar Sort Mode

public enum SidebarSortMode: String, Codable, CaseIterable, Sendable {
    case lastOpened
    case newest
    case oldest
    case manual

    public var label: String {
        switch self {
        case .lastOpened: return "Last Opened"
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .manual: return "Manual"
        }
    }
}

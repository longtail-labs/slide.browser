import Foundation
import SlideCLICore
import SlideDatabase

/// Bridges the JSON-RPC socket server to the TCA store.
/// Translates incoming SlideMethod calls into CLICommand actions and returns results.
@MainActor
public final class CommandServerBridge {
    private let server = CommandServer()
    private let router: CommandRouter
    private var dispatch: ((CLICommand) -> Void)?
    private var stateProvider: (() -> (objects: [TaskObject], projects: [OBXProject], activeProjectId: UUID?))?

    public init() {
        // Router delegates to self via captured closure
        var routeHandler: (@Sendable (SlideMethod, JSONRPCRequest) async -> JSONRPCResponse)?
        self.router = CommandRouter { method, request in
            guard let handler = routeHandler else {
                return .error(-32603, "Bridge not ready", id: request.id)
            }
            return await handler(method, request)
        }
        routeHandler = { [weak self] method, request in
            await self?.handleMethod(method, request: request) ?? .error(-32603, "Bridge deallocated", id: request.id)
        }
    }

    /// Start the socket server and wire it to the given dispatch closure.
    /// - Parameters:
    ///   - dispatch: Sends a CLICommand to the TCA store
    ///   - stateProvider: Returns current state for query methods
    public func start(
        dispatch: @escaping (CLICommand) -> Void,
        stateProvider: @escaping () -> (objects: [TaskObject], projects: [OBXProject], activeProjectId: UUID?)
    ) {
        self.dispatch = dispatch
        self.stateProvider = stateProvider

        let router = self.router
        do {
            try server.start { request in
                await router.route(request)
            }
        } catch {
            print("[CommandServerBridge] Failed to start: \(error)")
        }
    }

    public func stop() {
        server.stop()
    }

    // MARK: - Method Handling

    private func handleMethod(_ method: SlideMethod, request: JSONRPCRequest) async -> JSONRPCResponse {
        do {
            switch method {
            case .status:
                let result = SlideResults.Status(version: CommandServer.slideVersion)
                return .success(result, id: request.id)

            case .objectOpen:
                let params = try request.requireParams(SlideParams.ObjectOpen.self)
                let projectId = params.projectId.flatMap { UUID(uuidString: $0) }
                dispatch?(.objectOpen(
                    type: params.type,
                    url: params.url,
                    content: params.content,
                    cwd: params.cwd,
                    projectId: projectId
                ))
                return .success(SlideResults.Success(), id: request.id)

            case .objectFocus:
                let params = try request.requireParams(SlideParams.ObjectId.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.objectFocus(id: uuid))
                return .success(SlideResults.Success(), id: request.id)

            case .objectClose:
                let params = try request.requireParams(SlideParams.ObjectId.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.objectClose(id: uuid))
                return .success(SlideResults.Success(), id: request.id)

            case .objectBadge:
                let params = try request.requireParams(SlideParams.ObjectBadge.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.objectBadge(id: uuid, count: params.count))
                return .success(SlideResults.Success(), id: request.id)

            case .objectStart:
                let params = try request.requireParams(SlideParams.ObjectId.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.objectStart(id: uuid))
                return .success(SlideResults.Success(), id: request.id)

            case .objectStop:
                let params = try request.requireParams(SlideParams.ObjectStop.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.objectStop(id: uuid, badge: params.badge))
                return .success(SlideResults.Success(), id: request.id)

            case .objectAttention:
                let params = try request.requireParams(SlideParams.ObjectId.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.objectAttention(id: uuid))
                return .success(SlideResults.Success(), id: request.id)

            case .objectRename:
                let params = try request.requireParams(SlideParams.ObjectRename.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.objectRename(id: uuid, title: params.title))
                return .success(SlideResults.Success(), id: request.id)

            case .notify:
                let params = try request.requireParams(SlideParams.Notify.self)
                let objectId = params.objectId.flatMap { UUID(uuidString: $0) }
                dispatch?(.notify(title: params.title, body: params.body, objectId: objectId))
                return .success(SlideResults.Success(), id: request.id)

            case .projectSelect:
                let params = try request.requireParams(SlideParams.ProjectSelect.self)
                guard let uuid = UUID(uuidString: params.id) else {
                    return .error(-32602, "Invalid UUID: \(params.id)", id: request.id)
                }
                dispatch?(.projectSelect(id: uuid))
                return .success(SlideResults.Success(), id: request.id)

            case .objectList:
                let params = try? request.decodeParams(SlideParams.ObjectList.self)
                let state = stateProvider?()
                let objects = state?.objects ?? []
                let filtered: [TaskObject]
                if let pidStr = params?.projectId, let pid = UUID(uuidString: pidStr) {
                    filtered = objects.filter { $0.projectId == pid }
                } else {
                    filtered = objects
                }
                let infos = filtered.map {
                    SlideResults.ObjectInfo(
                        id: $0.uuid,
                        type: $0.kind.name,
                        title: $0.title ?? "Untitled"
                    )
                }
                return .success(infos, id: request.id)

            case .projectList:
                let state = stateProvider?()
                let projects = state?.projects ?? []
                let infos = projects.map {
                    SlideResults.ProjectInfo(id: $0.uuid, name: $0.name, icon: $0.icon)
                }
                return .success(infos, id: request.id)

            case .projectBadge:
                // Project badge is visual-only, handled via object aggregation
                return .success(SlideResults.Success(), id: request.id)

            case .identify:
                let state = stateProvider?()
                let result = SlideResults.Identity(
                    objectId: nil,
                    projectId: state?.activeProjectId?.uuidString,
                    socketPath: CommandServer.socketPath,
                    version: CommandServer.slideVersion
                )
                return .success(result, id: request.id)
            }
        } catch let error as CommandRouterError {
            return .error(-32602, error.localizedDescription ?? "Invalid params", id: request.id)
        } catch {
            return .error(-32603, error.localizedDescription, id: request.id)
        }
    }
}

// MARK: - OBXObjectKind name helper

extension OBXObjectKind {
    var name: String {
        switch self {
        case .link: return "browser"
        case .pdf: return "pdf"
        case .note: return "note"
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        case .terminal: return "terminal"
        case .codeEditor: return "code-editor"
        case .group: return "group"
        }
    }
}

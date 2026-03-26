import Dependencies
import Foundation

// MARK: - Database Client (Flat Object API + Projects)

public struct SlideDatabaseClient: Sendable {
    // Object operations
    public var fetchAllObjects: @Sendable @MainActor () async throws -> [TaskObject]
    public var fetchObject: @Sendable @MainActor (UUID) async throws -> TaskObject?
    public var createLinkObject: @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject
    public var createPDFObject: @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject
    public var createImageObject: @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject
    public var createVideoObject: @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject
    public var createAudioObject: @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject
    public var createNoteObject: @Sendable @MainActor (String, String, UUID?) async throws -> TaskObject
    public var createTerminalObject: @Sendable @MainActor (String, String, UUID?) async throws -> TaskObject
    public var updateObject: @Sendable @MainActor (TaskObject) async throws -> Void
    public var deleteObject: @Sendable @MainActor (UUID) async throws -> Void
    public var reorderObjects: @Sendable @MainActor ([UUID]) async throws -> Void

    // Project operations
    public var fetchAllProjects: @Sendable @MainActor () async throws -> [OBXProject]
    public var fetchProject: @Sendable @MainActor (UUID) async throws -> OBXProject?
    public var createProject: @Sendable @MainActor (String, String, String) async throws -> OBXProject
    public var updateProject: @Sendable @MainActor (OBXProject) async throws -> Void
    public var deleteProject: @Sendable @MainActor (UUID) async throws -> Void
    public var reorderProjects: @Sendable @MainActor ([UUID]) async throws -> Void
    public var assignObjectToProject: @Sendable @MainActor (UUID, UUID?) async throws -> Void
    public var fetchObjectsByProject: @Sendable @MainActor (UUID) async throws -> [TaskObject]

    // Access tracking
    public var updateObjectAccess: @Sendable @MainActor (UUID) async throws -> Void

    // Migration
    public var ensureScratchpadExists: @Sendable @MainActor () async throws -> Void

    // Reactive streams
    public var objectsStream: @Sendable () -> AsyncStream<[TaskObject]>
    public var projectsStream: @Sendable () -> AsyncStream<[OBXProject]>

    public init(
        fetchAllObjects: @escaping @Sendable @MainActor () async throws -> [TaskObject],
        fetchObject: @escaping @Sendable @MainActor (UUID) async throws -> TaskObject?,
        createLinkObject: @escaping @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject,
        createPDFObject: @escaping @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject,
        createImageObject: @escaping @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject,
        createVideoObject: @escaping @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject,
        createAudioObject: @escaping @Sendable @MainActor (String, URL, UUID?) async throws -> TaskObject,
        createNoteObject: @escaping @Sendable @MainActor (String, String, UUID?) async throws -> TaskObject,
        createTerminalObject: @escaping @Sendable @MainActor (String, String, UUID?) async throws -> TaskObject,
        updateObject: @escaping @Sendable @MainActor (TaskObject) async throws -> Void,
        deleteObject: @escaping @Sendable @MainActor (UUID) async throws -> Void,
        reorderObjects: @escaping @Sendable @MainActor ([UUID]) async throws -> Void,
        fetchAllProjects: @escaping @Sendable @MainActor () async throws -> [OBXProject],
        fetchProject: @escaping @Sendable @MainActor (UUID) async throws -> OBXProject?,
        createProject: @escaping @Sendable @MainActor (String, String, String) async throws -> OBXProject,
        updateProject: @escaping @Sendable @MainActor (OBXProject) async throws -> Void,
        deleteProject: @escaping @Sendable @MainActor (UUID) async throws -> Void,
        reorderProjects: @escaping @Sendable @MainActor ([UUID]) async throws -> Void,
        assignObjectToProject: @escaping @Sendable @MainActor (UUID, UUID?) async throws -> Void,
        fetchObjectsByProject: @escaping @Sendable @MainActor (UUID) async throws -> [TaskObject],
        updateObjectAccess: @escaping @Sendable @MainActor (UUID) async throws -> Void,
        ensureScratchpadExists: @escaping @Sendable @MainActor () async throws -> Void,
        objectsStream: @escaping @Sendable () -> AsyncStream<[TaskObject]>,
        projectsStream: @escaping @Sendable () -> AsyncStream<[OBXProject]>
    ) {
        self.fetchAllObjects = fetchAllObjects
        self.fetchObject = fetchObject
        self.createLinkObject = createLinkObject
        self.createPDFObject = createPDFObject
        self.createImageObject = createImageObject
        self.createVideoObject = createVideoObject
        self.createAudioObject = createAudioObject
        self.createNoteObject = createNoteObject
        self.createTerminalObject = createTerminalObject
        self.updateObject = updateObject
        self.deleteObject = deleteObject
        self.reorderObjects = reorderObjects
        self.fetchAllProjects = fetchAllProjects
        self.fetchProject = fetchProject
        self.createProject = createProject
        self.updateProject = updateProject
        self.deleteProject = deleteProject
        self.reorderProjects = reorderProjects
        self.assignObjectToProject = assignObjectToProject
        self.fetchObjectsByProject = fetchObjectsByProject
        self.updateObjectAccess = updateObjectAccess
        self.ensureScratchpadExists = ensureScratchpadExists
        self.objectsStream = objectsStream
        self.projectsStream = projectsStream
    }
}

// MARK: - Dependency Key

extension SlideDatabaseClient: DependencyKey {
    @MainActor
    public static var liveValue: Self {
        return Self(
            fetchAllObjects: {
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.fetchAllObjects()
            },
            fetchObject: { id in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.fetchObject(id: id)
            },
            createLinkObject: { title, url, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createLinkObject(title, url, projectId: projectId)
            },
            createPDFObject: { title, sourceFile, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createPDFObject(title, sourceFile, projectId: projectId)
            },
            createImageObject: { title, sourceFile, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createImageObject(title, sourceFile, projectId: projectId)
            },
            createVideoObject: { title, sourceFile, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createVideoObject(title, sourceFile, projectId: projectId)
            },
            createAudioObject: { title, sourceFile, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createAudioObject(title, sourceFile, projectId: projectId)
            },
            createNoteObject: { title, content, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createNoteObject(title, content, projectId: projectId)
            },
            createTerminalObject: { title, workingDirectory, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createTerminalObject(title, workingDirectory, projectId: projectId)
            },
            updateObject: { object in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.updateObject(object)
            },
            deleteObject: { id in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.deleteObject(id)
            },
            reorderObjects: { orderedIds in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.reorderObjects(orderedIds: orderedIds)
            },
            fetchAllProjects: {
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.fetchAllProjects()
            },
            fetchProject: { id in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.fetchProject(id: id)
            },
            createProject: { name, icon, colorHex in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.createProject(name: name, icon: icon, colorHex: colorHex)
            },
            updateProject: { project in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.updateProject(project)
            },
            deleteProject: { id in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.deleteProject(id)
            },
            reorderProjects: { orderedIds in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.reorderProjects(orderedIds: orderedIds)
            },
            assignObjectToProject: { objectId, projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.assignObjectToProject(objectId: objectId, projectId: projectId)
            },
            fetchObjectsByProject: { projectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                return try obx.fetchObjectsByProject(projectId: projectId)
            },
            updateObjectAccess: { objectId in
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.updateObjectAccess(objectId: objectId)
            },
            ensureScratchpadExists: {
                guard let obx = ObjectBoxDatabase.shared else { throw SlideDBError.notInitialized }
                try obx.ensureScratchpadExists()
            },
            objectsStream: {
                guard let obx = ObjectBoxDatabase.shared else { return AsyncStream { $0.finish() } }
                return obx.objectsStream()
            },
            projectsStream: {
                guard let obx = ObjectBoxDatabase.shared else { return AsyncStream { $0.finish() } }
                return obx.projectsStream()
            }
        )
    }

    public static var testValue: Self {
        Self(
            fetchAllObjects: { [] },
            fetchObject: { _ in nil },
            createLinkObject: { title, url, _ in
                TaskObject.createLink(title: title, url: url)
            },
            createPDFObject: { title, sourceFile, _ in
                TaskObject.createPDF(title: title, filePath: sourceFile, originalFileName: sourceFile.lastPathComponent)
            },
            createImageObject: { title, sourceFile, _ in
                TaskObject.createImage(title: title, filePath: sourceFile, originalFileName: sourceFile.lastPathComponent)
            },
            createVideoObject: { title, sourceFile, _ in
                TaskObject.createVideo(title: title, filePath: sourceFile, originalFileName: sourceFile.lastPathComponent)
            },
            createAudioObject: { title, sourceFile, _ in
                TaskObject.createAudio(title: title, filePath: sourceFile, originalFileName: sourceFile.lastPathComponent)
            },
            createNoteObject: { title, content, _ in
                TaskObject.createNote(title: title, content: content)
            },
            createTerminalObject: { title, workingDir, _ in
                TaskObject.createTerminal(title: title, workingDirectory: workingDir)
            },
            updateObject: { _ in },
            deleteObject: { _ in },
            reorderObjects: { _ in },
            fetchAllProjects: { [] },
            fetchProject: { _ in nil },
            createProject: { name, icon, colorHex in
                OBXProject(uuid: UUID().uuidString, name: name, icon: icon, colorHex: colorHex)
            },
            updateProject: { _ in },
            deleteProject: { _ in },
            reorderProjects: { _ in },
            assignObjectToProject: { _, _ in },
            fetchObjectsByProject: { _ in [] },
            updateObjectAccess: { _ in },
            ensureScratchpadExists: { },
            objectsStream: { AsyncStream { $0.finish() } },
            projectsStream: { AsyncStream { $0.finish() } }
        )
    }
}

extension DependencyValues {
    public var slideDatabase: SlideDatabaseClient {
        get { self[SlideDatabaseClient.self] }
        set { self[SlideDatabaseClient.self] = newValue }
    }
}

// MARK: - Error

public enum SlideDBError: LocalizedError {
    case notInitialized
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notInitialized: return "ObjectBox store not initialized"
        case .notFound: return "Object not found"
        }
    }
}

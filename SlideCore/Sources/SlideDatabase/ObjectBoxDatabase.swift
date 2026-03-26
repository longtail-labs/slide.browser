// A lightweight ObjectBox-backed database wrapper for the flat content browser.

import Foundation
import ObjectBox

public final class ObjectBoxDatabase {
    public static var shared: ObjectBoxDatabase?

    let store: Store
    private let objectBox: Box<OBXObject>
    private let projectBox: Box<OBXProject>

    public static func initialize(at directoryURL: URL) throws {
        let store = try Store(directoryPath: directoryURL.path)
        let db = ObjectBoxDatabase(store: store)
        self.shared = db
    }

    private init(store: Store) {
        self.store = store
        self.objectBox = store.box(for: OBXObject.self)
        self.projectBox = store.box(for: OBXProject.self)
    }

    // MARK: - Query helpers

    private func findObject(uuid: String) throws -> OBXObject? {
        let query = try objectBox.query { OBXObject.uuid == uuid }.build()
        return try query.findFirst()
    }

    private func findProject(uuid: String) throws -> OBXProject? {
        let query = try projectBox.query { OBXProject.uuid == uuid }.build()
        return try query.findFirst()
    }

    // MARK: - Fetch

    public func fetchAllObjects() throws -> [TaskObject] {
        try objectBox.query().ordered(by: OBXObject.sortOrder).build().find()
    }

    public func fetchObject(id: UUID) throws -> TaskObject? {
        try findObject(uuid: id.uuidString)
    }

    // MARK: - Create helpers

    private func saveObject(_ object: OBXObject, projectId: UUID?) throws -> TaskObject {
        // Get next sort order via PropertyQuery (no full-table scan)
        let maxOrder: Int = (try? objectBox.query().build()
            .property(OBXObject.sortOrder).max()) ?? -1
        object.sortOrder = maxOrder + 1
        object.lastAccessedAt = Date()
        // Assign to project if specified
        if let projectId = projectId {
            if let project = try findProject(uuid: projectId.uuidString) {
                object.project.target = project
            }
        }
        try objectBox.put(object)
        return object
    }

    public func createLinkObject(_ title: String, _ url: URL, projectId: UUID? = nil) throws -> TaskObject {
        let payload = OBXJSONPayload.link(.init(url: url.absoluteString, favicon: nil, preview: nil))
        let o = OBXObject(uuid: UUID().uuidString, kind: .link, payload: payload)
        o.displayName = title
        return try saveObject(o, projectId: projectId)
    }

    public func createPDFObject(_ title: String, _ sourceFile: URL, projectId: UUID? = nil) throws -> TaskObject {
        let objectId = UUID()
        let storedPath = try FileManager.default.copyFileToAppContainer(from: sourceFile, objectId: objectId)
        let metadata = FileManager.extractMetadata(from: sourceFile)
        let payload = OBXJSONPayload.pdf(.init(
            filePath: storedPath.path,
            pageCount: metadata.pageCount ?? 0,
            currentPage: 1,
            originalFileName: sourceFile.lastPathComponent
        ))
        let o = OBXObject(uuid: objectId.uuidString, kind: .pdf, payload: payload)
        o.displayName = title
        return try saveObject(o, projectId: projectId)
    }

    public func createImageObject(_ title: String, _ sourceFile: URL, projectId: UUID? = nil) throws -> TaskObject {
        let objectId = UUID()
        let storedPath = try FileManager.default.copyFileToAppContainer(from: sourceFile, objectId: objectId)
        let metadata = FileManager.extractMetadata(from: sourceFile)
        let fileSize = FileManager.default.fileSize(at: sourceFile) ?? 0
        let mimeType = FileManager.mimeType(for: sourceFile)
        let payload = OBXJSONPayload.image(.init(
            filePath: storedPath.path,
            mimeType: mimeType,
            size: fileSize,
            width: metadata.width,
            height: metadata.height,
            thumbnail: nil,
            originalFileName: sourceFile.lastPathComponent
        ))
        let o = OBXObject(uuid: objectId.uuidString, kind: .image, payload: payload)
        o.displayName = title
        return try saveObject(o, projectId: projectId)
    }

    public func createVideoObject(_ title: String, _ sourceFile: URL, projectId: UUID? = nil) throws -> TaskObject {
        let objectId = UUID()
        let storedPath = try FileManager.default.copyFileToAppContainer(from: sourceFile, objectId: objectId)
        let metadata = FileManager.extractMetadata(from: sourceFile)
        let fileSize = FileManager.default.fileSize(at: sourceFile) ?? 0
        let mimeType = FileManager.mimeType(for: sourceFile)
        let payload = OBXJSONPayload.video(.init(
            filePath: storedPath.path,
            mimeType: mimeType,
            size: fileSize,
            duration: metadata.duration,
            width: metadata.width,
            height: metadata.height,
            thumbnail: nil,
            originalFileName: sourceFile.lastPathComponent
        ))
        let o = OBXObject(uuid: objectId.uuidString, kind: .video, payload: payload)
        o.displayName = title
        return try saveObject(o, projectId: projectId)
    }

    public func createAudioObject(_ title: String, _ sourceFile: URL, projectId: UUID? = nil) throws -> TaskObject {
        let objectId = UUID()
        let storedPath = try FileManager.default.copyFileToAppContainer(from: sourceFile, objectId: objectId)
        let metadata = FileManager.extractMetadata(from: sourceFile)
        let fileSize = FileManager.default.fileSize(at: sourceFile) ?? 0
        let mimeType = FileManager.mimeType(for: sourceFile)
        let payload = OBXJSONPayload.audio(.init(
            filePath: storedPath.path,
            mimeType: mimeType,
            size: fileSize,
            duration: metadata.duration,
            artist: nil,
            album: nil,
            originalFileName: sourceFile.lastPathComponent
        ))
        let o = OBXObject(uuid: objectId.uuidString, kind: .audio, payload: payload)
        o.displayName = title
        return try saveObject(o, projectId: projectId)
    }

    public func createNoteObject(_ title: String, _ content: String, projectId: UUID? = nil) throws -> TaskObject {
        let payload = OBXJSONPayload.note(.init(content: content))
        let o = OBXObject(uuid: UUID().uuidString, kind: .note, payload: payload)
        o.displayName = title
        return try saveObject(o, projectId: projectId)
    }

    public func createTerminalObject(_ title: String, _ workingDirectory: String, projectId: UUID? = nil) throws -> TaskObject {
        let payload = OBXJSONPayload.terminal(.init(workingDirectory: workingDirectory))
        let o = OBXObject(uuid: UUID().uuidString, kind: .terminal, payload: payload)
        o.displayName = title
        return try saveObject(o, projectId: projectId)
    }

    // MARK: - Update / Delete

    public func updateObject(_ object: TaskObject) throws {
        object.updatedAt = Date()
        try objectBox.put(object)
    }

    public func deleteObject(_ id: UUID) throws {
        guard let obx = try findObject(uuid: id.uuidString) else { return }
        // Delete associated media files if any
        FileManager.default.deleteMediaForObject(id)
        try objectBox.remove(obx)
    }

    public func reorderObjects(orderedIds: [UUID]) throws {
        for (index, id) in orderedIds.enumerated() {
            guard let obj = try findObject(uuid: id.uuidString) else { continue }
            if obj.sortOrder != index {
                obj.sortOrder = index
                obj.updatedAt = Date()
                try objectBox.put(obj)
            }
        }
    }

    // MARK: - Projects

    public func fetchAllProjects() throws -> [OBXProject] {
        try projectBox.query().ordered(by: OBXProject.sortOrder).build().find()
    }

    public func fetchProject(id: UUID) throws -> OBXProject? {
        try findProject(uuid: id.uuidString)
    }

    public func createProject(name: String, icon: String = "📁", colorHex: String = "#6B7280") throws -> OBXProject {
        let maxOrder: Int = (try? projectBox.query().build()
            .property(OBXProject.sortOrder).max()) ?? -1
        let project = OBXProject(uuid: UUID().uuidString, name: name, icon: icon, colorHex: colorHex)
        project.sortOrder = maxOrder + 1
        try projectBox.put(project)
        return project
    }

    public func updateProject(_ project: OBXProject) throws {
        project.updatedAt = Date()
        try projectBox.put(project)
    }

    public func deleteProject(_ id: UUID) throws {
        guard let project = try findProject(uuid: id.uuidString) else { return }
        // Don't allow deleting the Scratchpad
        guard project.uuid != scratchpadProjectUUID else { return }
        // Move objects from this project to Scratchpad
        let scratchpad = try findProject(uuid: scratchpadProjectUUID)
        for obj in Array(project.objects) {
            obj.project.target = scratchpad
            obj.updatedAt = Date()
            try objectBox.put(obj)
        }
        try projectBox.remove(project)
    }

    public func reorderProjects(orderedIds: [UUID]) throws {
        for (index, id) in orderedIds.enumerated() {
            guard let project = try findProject(uuid: id.uuidString) else { continue }
            if project.sortOrder != index {
                project.sortOrder = index
                project.updatedAt = Date()
                try projectBox.put(project)
            }
        }
    }

    public func assignObjectToProject(objectId: UUID, projectId: UUID?) throws {
        guard let obj = try findObject(uuid: objectId.uuidString) else { return }
        if let projectId = projectId {
            obj.project.target = try findProject(uuid: projectId.uuidString)
        } else {
            obj.project.target = nil
        }
        obj.updatedAt = Date()
        try objectBox.put(obj)
    }

    public func fetchObjectsByProject(projectId: UUID) throws -> [TaskObject] {
        guard let project = try findProject(uuid: projectId.uuidString) else { return [] }
        return Array(project.objects).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Ensures the Scratchpad project always exists — called on every launch
    public func ensureScratchpadExists() throws {
        if try findProject(uuid: scratchpadProjectUUID) == nil {
            let scratchpad = OBXProject(uuid: scratchpadProjectUUID, name: "Scratchpad", icon: "📝", colorHex: "#6B7280")
            scratchpad.sortOrder = 0
            try projectBox.put(scratchpad)
        }
    }

    // MARK: - Open/Access tracking

    public func updateObjectAccess(objectId: UUID) throws {
        guard let obj = try findObject(uuid: objectId.uuidString) else { return }
        obj.lastAccessedAt = Date()
        obj.updatedAt = Date()
        try objectBox.put(obj)
    }

    // MARK: - Subscriptions

    public func objectsStream() -> AsyncStream<[TaskObject]> {
        AsyncStream { continuation in
            guard let query = try? objectBox.query().ordered(by: OBXObject.sortOrder).build() else {
                continuation.finish()
                return
            }

            // Send initial snapshot (pre-sorted by DB)
            if let current = try? query.find() {
                continuation.yield(current)
            }

            let obs = query.subscribe { objects, _ in
                continuation.yield(objects)
            }

            let holder = ObjectsSubscriptionHolder(query: query, observer: obs)
            continuation.onTermination = { _ in
                holder.observer = nil
                _ = holder
            }
        }
    }

    public func projectsStream() -> AsyncStream<[OBXProject]> {
        AsyncStream { continuation in
            guard let query = try? projectBox.query().ordered(by: OBXProject.sortOrder).build() else {
                continuation.finish()
                return
            }

            if let current = try? query.find() {
                continuation.yield(current)
            }

            let obs = query.subscribe { projects, _ in
                continuation.yield(projects)
            }

            let holder = ProjectsSubscriptionHolder(query: query, observer: obs)
            continuation.onTermination = { _ in
                holder.observer = nil
                _ = holder
            }
        }
    }

    final class ObjectsSubscriptionHolder {
        let query: Query<OBXObject>
        var observer: Observer?
        init(query: Query<OBXObject>, observer: Observer?) {
            self.query = query
            self.observer = observer
        }
    }

    final class ProjectsSubscriptionHolder {
        let query: Query<OBXProject>
        var observer: Observer?
        init(query: Query<OBXProject>, observer: Observer?) {
            self.query = query
            self.observer = observer
        }
    }
}

import Foundation
import ObjectBox

// MARK: - Observable Object Stream

/// Provides reactive object updates using ObjectBox Query observers
public struct ObjectObserver {
    private let database: ObjectBoxDatabase

    public init(database: ObjectBoxDatabase = ObjectBoxDatabase.shared!) {
        self.database = database
    }

    /// Stream all objects with reactive updates
    public func observeAllObjects() -> AsyncStream<[TaskObject]> {
        database.objectsStream()
    }

    /// Stream all projects with reactive updates
    public func observeAllProjects() -> AsyncStream<[OBXProject]> {
        database.projectsStream()
    }

    /// Observe a specific object
    public func observeObject(id: UUID) -> AsyncStream<TaskObject?> {
        AsyncStream { continuation in
            let objectBox = database.store.box(for: OBXObject.self)

            // Create query for specific object
            guard let query = try? objectBox.query { OBXObject.uuid == id.uuidString }.build() else {
                continuation.finish()
                return
            }

            // Send initial value
            if let current = try? query.findFirst() {
                continuation.yield(current)
            }

            // Subscribe to changes
            let observer = query.subscribe { objects, _ in
                continuation.yield(objects.first)
            }

            // Keep observer alive
            let holder = ObserverHolder(observer: observer)
            continuation.onTermination = { _ in
                holder.observer = nil
                _ = holder
            }
        }
    }
}

// MARK: - Observer Holder

private final class ObserverHolder {
    var observer: Observer?
    init(observer: Observer?) {
        self.observer = observer
    }
}

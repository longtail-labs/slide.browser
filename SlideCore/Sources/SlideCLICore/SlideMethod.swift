import Foundation

/// Dot-namespaced method identifiers for the Slide JSON-RPC API.
public enum SlideMethod: String, Codable, Sendable {
    // Status
    case status

    // Objects
    case objectList       = "object.list"
    case objectOpen       = "object.open"
    case objectFocus      = "object.focus"
    case objectClose      = "object.close"
    case objectBadge      = "object.badge"
    case objectStart      = "object.start"
    case objectStop       = "object.stop"
    case objectAttention  = "object.attention"
    case objectRename     = "object.rename"

    // Projects
    case projectList      = "project.list"
    case projectSelect    = "project.select"
    case projectBadge     = "project.badge"
    case projectCreate    = "project.create"

    // Notifications
    case notify

    // Identity
    case identify
}

// MARK: - Typed Parameter Structs

public enum SlideParams {
    public struct ObjectOpen: Codable, Sendable {
        public let type: String
        public var url: String?
        public var content: String?
        public var cwd: String?
        public var projectId: String?
    }

    public struct ObjectId: Codable, Sendable {
        public let id: String
    }

    public struct ObjectBadge: Codable, Sendable {
        public let id: String
        public let count: Int
    }

    public struct ObjectStop: Codable, Sendable {
        public let id: String
        public var badge: Int?
    }

    public struct ProjectSelect: Codable, Sendable {
        public let id: String
    }

    public struct ProjectBadge: Codable, Sendable {
        public let id: String
        public let count: Int
    }

    public struct ProjectCreate: Codable, Sendable {
        public let name: String
        public var icon: String?
        public var color: String?
    }

    public struct Notify: Codable, Sendable {
        public let title: String
        public var body: String?
        public var objectId: String?
    }

    public struct ObjectRename: Codable, Sendable {
        public let id: String
        public let title: String
    }

    public struct ObjectList: Codable, Sendable {
        public var projectId: String?
    }
}

// MARK: - Result Structs

public enum SlideResults {
    public struct Status: Codable, Sendable {
        public let running: Bool
        public let version: String

        public init(running: Bool = true, version: String) {
            self.running = running
            self.version = version
        }
    }

    public struct ObjectResult: Codable, Sendable {
        public let objectId: String
        public let success: Bool

        public init(objectId: String, success: Bool = true) {
            self.objectId = objectId
            self.success = success
        }
    }

    public struct Success: Codable, Sendable {
        public let success: Bool
        public init(success: Bool = true) { self.success = success }
    }

    public struct Identity: Codable, Sendable {
        public let objectId: String?
        public let projectId: String?
        public let socketPath: String
        public let version: String

        public init(objectId: String?, projectId: String?, socketPath: String, version: String) {
            self.objectId = objectId
            self.projectId = projectId
            self.socketPath = socketPath
            self.version = version
        }
    }

    public struct ObjectInfo: Codable, Sendable {
        public let id: String
        public let type: String
        public let title: String

        public init(id: String, type: String, title: String) {
            self.id = id
            self.type = type
            self.title = title
        }
    }

    public struct ProjectInfo: Codable, Sendable {
        public let id: String
        public let name: String
        public let icon: String

        public init(id: String, name: String, icon: String) {
            self.id = id
            self.name = name
            self.icon = icon
        }
    }

    public struct ProjectCreateResult: Codable, Sendable {
        public let id: String
        public let name: String
        public let icon: String
        public let success: Bool

        public init(id: String, name: String, icon: String, success: Bool = true) {
            self.id = id
            self.name = name
            self.icon = icon
            self.success = success
        }
    }
}

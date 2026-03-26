// This file contains ObjectBox entity models and converters.
// It is only compiled when ObjectBox is available.

import Foundation
import ObjectBox

// MARK: - Activity State (transient, not persisted)

public enum ObjectActivityState: String, Codable, Sendable {
    case idle          // default — no indicator
    case active        // pulsing blue/green — agent is working
    case attention     // pulsing amber — needs user input/permission
}

// MARK: - Object Kind

public enum OBXObjectKind: Int, Codable {
    case link = 0
    case pdf = 1
    case note = 2
    case image = 3
    case video = 4
    case audio = 5
    case terminal = 6
    case group = 7
    case codeEditor = 8
}

// MARK: - Variant payloads

public struct OBXLinkData: Codable {
    var url: String
    var favicon: String?
    var preview: String?
}

public struct OBXPDFData: Codable {
    public var filePath: String  // Path relative to app container
    public var pageCount: Int
    public var currentPage: Int
    public var originalFileName: String?  // Original file name for display
}

public struct OBXNoteData: Codable {
    var content: String
}

public struct OBXImageData: Codable {
    public var filePath: String  // Path relative to app container
    public var mimeType: String
    public var size: Int
    public var width: Int?
    public var height: Int?
    public var thumbnail: String?
    public var originalFileName: String?  // Original file name for display
}

public struct OBXVideoData: Codable {
    public var filePath: String  // Path relative to app container
    public var mimeType: String
    public var size: Int
    public var duration: Double?  // Duration in seconds
    public var width: Int?
    public var height: Int?
    public var thumbnail: String?
    public var originalFileName: String?  // Original file name for display
}

public struct OBXAudioData: Codable {
    public var filePath: String  // Path relative to app container
    public var mimeType: String
    public var size: Int
    public var duration: Double?  // Duration in seconds
    public var artist: String?
    public var album: String?
    public var originalFileName: String?  // Original file name for display
}

public struct OBXTerminalData: Codable {
    public var workingDirectory: String
    public var shell: String?
    public var needsAttention: Bool
    public var badgeCount: Int

    public init(workingDirectory: String = "~", shell: String? = nil, needsAttention: Bool = false, badgeCount: Int = 0) {
        self.workingDirectory = workingDirectory
        self.shell = shell
        self.needsAttention = needsAttention
        self.badgeCount = badgeCount
    }

    // Backwards-compatible decoding for existing data without badgeCount
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        shell = try container.decodeIfPresent(String.self, forKey: .shell)
        needsAttention = try container.decodeIfPresent(Bool.self, forKey: .needsAttention) ?? false
        badgeCount = try container.decodeIfPresent(Int.self, forKey: .badgeCount) ?? 0
    }
}

public struct OBXCodeEditorData: Codable {
    public var filePath: String?        // File-backed mode: read/write from disk
    public var language: String         // CodeLanguage rawValue
    public var content: String?         // DB-stored mode: content in payload

    public init(filePath: String? = nil, language: String = "plain", content: String? = nil) {
        self.filePath = filePath
        self.language = language
        self.content = content
    }
}

public struct OBXGroupData: Codable {
    public var childUUIDs: [String]

    public init(childUUIDs: [String] = []) {
        self.childUUIDs = childUUIDs
    }
}

public struct OBXInvalidPayloadData: Codable {
    public var rawData: Data
    public var errorDescription: String

    public init(rawData: Data, errorDescription: String) {
        self.rawData = rawData
        self.errorDescription = errorDescription
    }
}

// Type-erased union payload
public enum OBXJSONPayload: Codable {
    case link(OBXLinkData)
    case pdf(OBXPDFData)
    case note(OBXNoteData)
    case image(OBXImageData)
    case video(OBXVideoData)
    case audio(OBXAudioData)
    case terminal(OBXTerminalData)
    case group(OBXGroupData)
    case codeEditor(OBXCodeEditorData)
    case invalid(OBXInvalidPayloadData)
}

// MARK: - Converter between payload <-> Data

public enum OBXJSONPayloadConverter {
    // Generator expects `convert` overloads.
    public static func convert(_ entityValue: OBXJSONPayload) -> [UInt8] {
        if case .invalid(let payload) = entityValue {
            return [UInt8](payload.rawData)
        }

        do { return [UInt8](try JSONEncoder().encode(entityValue)) } catch { return [] }
    }
    public static func convert(_ dbValue: [UInt8]) -> OBXJSONPayload {
        do { return try JSONDecoder().decode(OBXJSONPayload.self, from: Data(dbValue)) } catch {
            print("[OBXJSONPayloadConverter] Failed to decode payload: \(error)")
            return .invalid(.init(rawData: Data(dbValue), errorDescription: String(describing: error)))
        }
    }
}

// MARK: - Entities

// objectbox: entity
public final class OBXProject: Equatable {
    public var id: Id = 0
    // objectbox: unique
    public var uuid: String = UUID().uuidString
    public var name: String = ""
    // Emoji string or image path
    public var icon: String = "📁"
    public var colorHex: String = "#6B7280"
    // objectbox: index
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // objectbox: backlink = "project"
    public var objects: ToMany<OBXObject> = nil

    public init() {}
    public init(uuid: String, name: String, icon: String = "📁", colorHex: String = "#6B7280") {
        self.uuid = uuid
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var uuidValue: UUID { UUID(uuidString: uuid) ?? UUID() }

    public static func == (lhs: OBXProject, rhs: OBXProject) -> Bool {
        lhs.uuid == rhs.uuid
            && lhs.name == rhs.name
            && lhs.icon == rhs.icon
            && lhs.colorHex == rhs.colorHex
            && lhs.sortOrder == rhs.sortOrder
            && lhs.updatedAt == rhs.updatedAt
    }
}

extension OBXProject: Identifiable {}

/// Well-known UUID for the default Scratchpad project
public let scratchpadProjectUUID = "00000000-0000-0000-0000-000000000001"

// objectbox: entity
public final class OBXObject {
    public var id: Id = 0
    // objectbox: unique
    public var uuid: String = UUID().uuidString
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // objectbox: index
    // objectbox: convert = { "default": ".link" }
    public var kind: OBXObjectKind

    // objectbox: convert = { "dbType": "Data", "converter": "OBXJSONPayloadConverter" }
    public var payload: OBXJSONPayload

    // Title promoted out of payload — indexable, queryable
    // objectbox: index
    public var displayName: String = ""

    // User-set custom name — when non-empty, takes precedence over displayName
    // and blocks auto-title updates from OSC/webview metadata
    public var customName: String = ""

    // objectbox: index
    public var sortOrder: Int = 0
    public var lastAccessedAt: Date? = nil

    // Project relation
    public var project: ToOne<OBXProject> = nil

    public init(uuid: String, kind: OBXObjectKind, payload: OBXJSONPayload) {
        self.createdAt = Date()
        self.updatedAt = Date()
        self.kind = kind
        self.payload = payload
        self.uuid = uuid
    }
    public init() {
        self.kind = .link
        self.payload = .link(.init(url: "", favicon: nil, preview: nil))
    }
}

// MARK: - Identifiable + UUID convenience

public typealias ObjectType = OBXObjectKind
public typealias TaskObject = OBXObject

extension OBXObject: Identifiable {}

// MARK: - Equatable conformance for TCA

extension OBXObject: Equatable {
    public static func == (lhs: OBXObject, rhs: OBXObject) -> Bool {
        lhs.uuid == rhs.uuid
            && lhs.updatedAt == rhs.updatedAt
            && lhs.sortOrder == rhs.sortOrder
            && lhs.customName == rhs.customName
    }
}

public extension OBXObject {
    /// Returns customName if set, otherwise displayName
    var displayTitle: String {
        customName.isEmpty ? displayName : customName
    }

    var uuidValue: UUID { UUID(uuidString: uuid) ?? UUID() }
    var objectType: ObjectType {
        get { kind }
        set { kind = newValue }
    }
    var projectId: UUID? {
        get { project.target?.uuidValue }
    }
    var title: String? {
        get { displayName.isEmpty ? nil : displayName }
        set { displayName = newValue ?? "" }
    }
    var url: URL? {
        get {
            if case .link(let d) = payload { return URL(string: d.url) }
            return nil
        }
        set {
            if case .link(var d) = payload { d.url = newValue?.absoluteString ?? d.url; payload = .link(d) }
        }
    }
    var favicon: String? {
        get { if case .link(let d) = payload { return d.favicon } else { return nil } }
        set { if case .link(var d) = payload { d.favicon = newValue; payload = .link(d) } }
    }
    var preview: String? {
        get { if case .link(let d) = payload { return d.preview } else { return nil } }
        set { if case .link(var d) = payload { d.preview = newValue; payload = .link(d) } }
    }
    var filePath: URL? {
        get {
            switch payload {
            case .pdf(let d): return URL(fileURLWithPath: d.filePath)
            case .image(let d): return URL(fileURLWithPath: d.filePath)
            case .video(let d): return URL(fileURLWithPath: d.filePath)
            case .audio(let d): return URL(fileURLWithPath: d.filePath)
            default: return nil
            }
        }
        set {
            guard let newValue = newValue else { return }
            switch payload {
            case .pdf(var d): d.filePath = newValue.path; payload = .pdf(d)
            case .image(var d): d.filePath = newValue.path; payload = .image(d)
            case .video(var d): d.filePath = newValue.path; payload = .video(d)
            case .audio(var d): d.filePath = newValue.path; payload = .audio(d)
            default: break
            }
        }
    }
    var pageCount: Int? {
        get { if case .pdf(let d) = payload { return d.pageCount } else { return nil } }
        set { if case .pdf(var d) = payload { d.pageCount = newValue ?? d.pageCount; payload = .pdf(d) } }
    }
    var currentPage: Int? {
        get { if case .pdf(let d) = payload { return d.currentPage } else { return nil } }
        set { if case .pdf(var d) = payload { d.currentPage = newValue ?? d.currentPage; payload = .pdf(d) } }
    }
    var content: String? {
        get { if case .note(let d) = payload { return d.content } else { return nil } }
        set { if case .note(var d) = payload { d.content = newValue ?? d.content; payload = .note(d) } }
    }
    // Factories to mirror previous API
    static func createLink(title: String, url: URL, favicon: String? = nil) -> OBXObject {
        let p = OBXJSONPayload.link(.init(url: url.absoluteString, favicon: favicon, preview: nil))
        let o = OBXObject(uuid: UUID().uuidString, kind: .link, payload: p)
        o.displayName = title
        return o
    }
    static func createPDF(title: String, filePath: URL, pageCount: Int = 0, originalFileName: String? = nil) -> OBXObject {
        let p = OBXJSONPayload.pdf(.init(filePath: filePath.path, pageCount: pageCount, currentPage: 1, originalFileName: originalFileName))
        let o = OBXObject(uuid: UUID().uuidString, kind: .pdf, payload: p)
        o.displayName = title
        return o
    }

    static func createImage(title: String, filePath: URL, mimeType: String = "image/jpeg", size: Int = 0, originalFileName: String? = nil) -> OBXObject {
        let p = OBXJSONPayload.image(.init(filePath: filePath.path, mimeType: mimeType, size: size, width: nil, height: nil, thumbnail: nil, originalFileName: originalFileName))
        let o = OBXObject(uuid: UUID().uuidString, kind: .image, payload: p)
        o.displayName = title
        return o
    }

    static func createVideo(title: String, filePath: URL, mimeType: String = "video/mp4", size: Int = 0, originalFileName: String? = nil) -> OBXObject {
        let p = OBXJSONPayload.video(.init(filePath: filePath.path, mimeType: mimeType, size: size, duration: nil, width: nil, height: nil, thumbnail: nil, originalFileName: originalFileName))
        let o = OBXObject(uuid: UUID().uuidString, kind: .video, payload: p)
        o.displayName = title
        return o
    }

    static func createAudio(title: String, filePath: URL, mimeType: String = "audio/mpeg", size: Int = 0, originalFileName: String? = nil) -> OBXObject {
        let p = OBXJSONPayload.audio(.init(filePath: filePath.path, mimeType: mimeType, size: size, duration: nil, artist: nil, album: nil, originalFileName: originalFileName))
        let o = OBXObject(uuid: UUID().uuidString, kind: .audio, payload: p)
        o.displayName = title
        return o
    }
    static func createNote(title: String, content: String = "") -> OBXObject {
        let p = OBXJSONPayload.note(.init(content: content))
        let o = OBXObject(uuid: UUID().uuidString, kind: .note, payload: p)
        o.displayName = title
        return o
    }
    static func createTerminal(title: String = "Terminal", workingDirectory: String = "~", shell: String? = nil) -> OBXObject {
        let p = OBXJSONPayload.terminal(.init(workingDirectory: workingDirectory, shell: shell))
        let o = OBXObject(uuid: UUID().uuidString, kind: .terminal, payload: p)
        o.displayName = title
        return o
    }
    static func createCodeEditor(title: String, filePath: String? = nil, language: String = "plain", content: String? = nil) -> OBXObject {
        let p = OBXJSONPayload.codeEditor(.init(filePath: filePath, language: language, content: content))
        let o = OBXObject(uuid: UUID().uuidString, kind: .codeEditor, payload: p)
        o.displayName = title
        return o
    }

    // Code editor convenience
    var codeEditorData: OBXCodeEditorData? {
        if case .codeEditor(let d) = payload { return d }
        return nil
    }
}

// Allow queries on enum property
extension OBXObjectKind: EntityPropertyTypeConvertible {
    public static var entityPropertyType: PropertyType { .int }
}

import Foundation

// Centralized storage configuration for database and media paths.
// Set `rootFolderName` once at app startup (e.g., in SlideApp) and
// all path computations will use it.
public enum StorageConfig {
    // Root directory name under Application Support.
    #if DEBUG
    public static var rootFolderName: String = "SlideBrowser.DEBUG"
    #else
    public static var rootFolderName: String = "SlideBrowser"
    #endif
    // Subfolder names.
    public static var databaseFolderName: String = "Database"
    public static var mediaFolderName: String = "Media"

    public static func appSupportURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    public static func rootURL() throws -> URL {
        try appSupportURL().appendingPathComponent(rootFolderName, isDirectory: true)
    }

    public static func databaseURL() throws -> URL {
        try rootURL().appendingPathComponent(databaseFolderName, isDirectory: true)
    }

    public static func mediaURL() throws -> URL {
        try rootURL().appendingPathComponent(mediaFolderName, isDirectory: true)
    }

    // Ensure base folders exist (idempotent).
    public static func ensureBaseDirectories() throws {
        let root = try rootURL()
        let db = try databaseURL()
        let media = try mediaURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: db, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true, attributes: nil)
    }
}


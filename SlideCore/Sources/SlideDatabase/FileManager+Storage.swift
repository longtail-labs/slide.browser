import Foundation
import UniformTypeIdentifiers

public enum FileStorageError: Error {
    case invalidURL
    case copyFailed(Error)
    case containerCreationFailed(Error)
    case unsupportedFileType
}

public extension FileManager {
    // MARK: - App Container Management
    
    static var slideMediaDirectory: URL? {
        guard let mediaDir = try? StorageConfig.mediaURL() else { return nil }
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: mediaDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return mediaDir
    }
    
    // MARK: - File Operations
    
    func copyFileToAppContainer(from sourceURL: URL, objectId: UUID) throws -> URL {
        guard let mediaDir = FileManager.slideMediaDirectory else {
            throw FileStorageError.containerCreationFailed(NSError(domain: "FileManager", code: 1))
        }
        
        // Create subdirectory for this object
        let objectDir = mediaDir.appendingPathComponent(objectId.uuidString, isDirectory: true)
        try createDirectory(at: objectDir, withIntermediateDirectories: true, attributes: nil)
        
        // Preserve original filename
        let fileName = sourceURL.lastPathComponent
        let destinationURL = objectDir.appendingPathComponent(fileName)
        
        // Remove existing file if present
        if fileExists(atPath: destinationURL.path) {
            try removeItem(at: destinationURL)
        }
        
        // Copy file
        do {
            try copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw FileStorageError.copyFailed(error)
        }
    }
    
    func deleteMediaForObject(_ objectId: UUID) {
        guard let mediaDir = FileManager.slideMediaDirectory else { return }
        let objectDir = mediaDir.appendingPathComponent(objectId.uuidString, isDirectory: true)
        try? removeItem(at: objectDir)
    }
    
    // MARK: - File Type Detection
    
    static func detectFileType(for url: URL) -> FileType {
        let pathExtension = url.pathExtension.lowercased()
        
        // Try to determine from UTType
        if let type = UTType(filenameExtension: pathExtension) {
            switch type {
            case _ where type.conforms(to: .pdf):
                return .pdf
            case _ where type.conforms(to: .image):
                return .image
            case _ where type.conforms(to: .movie) || type.conforms(to: .video):
                return .video
            case _ where type.conforms(to: .audio):
                return .audio
            default:
                break
            }
        }
        
        // Fallback to extension-based detection
        switch pathExtension {
        // PDF
        case "pdf":
            return .pdf
        
        // Images
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg":
            return .image
        
        // Videos
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpg", "mpeg":
            return .video
        
        // Audio
        case "mp3", "wav", "aac", "m4a", "flac", "ogg", "wma", "aiff", "alac":
            return .audio
        
        default:
            return .unknown
        }
    }
    
    static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
    
    // MARK: - File Info
    
    func fileSize(at url: URL) -> Int? {
        guard let attributes = try? attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }
    
    enum FileType {
        case pdf
        case image
        case video
        case audio
        case unknown
    }
}

// MARK: - Media Metadata Extraction

import CoreGraphics
import AVFoundation
import PDFKit

public struct MediaMetadata {
    public let width: Int?
    public let height: Int?
    public let duration: Double?
    public let pageCount: Int?
    
    public init(width: Int? = nil, height: Int? = nil, duration: Double? = nil, pageCount: Int? = nil) {
        self.width = width
        self.height = height
        self.duration = duration
        self.pageCount = pageCount
    }
}

public extension FileManager {
    static func extractMetadata(from url: URL) -> MediaMetadata {
        let fileType = detectFileType(for: url)
        
        switch fileType {
        case .pdf:
            return extractPDFMetadata(from: url)
        case .image:
            return extractImageMetadata(from: url)
        case .video:
            return extractVideoMetadata(from: url)
        case .audio:
            return extractAudioMetadata(from: url)
        case .unknown:
            return MediaMetadata()
        }
    }
    
    private static func extractPDFMetadata(from url: URL) -> MediaMetadata {
        guard let document = PDFDocument(url: url) else {
            return MediaMetadata()
        }
        return MediaMetadata(pageCount: document.pageCount)
    }
    
    private static func extractImageMetadata(from url: URL) -> MediaMetadata {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return MediaMetadata()
        }
        
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int
        
        return MediaMetadata(width: width, height: height)
    }
    
    private static func extractVideoMetadata(from url: URL) -> MediaMetadata {
        let asset = AVAsset(url: url)
        
        // Get duration
        let duration = CMTimeGetSeconds(asset.duration)
        
        // Get dimensions
        var width: Int?
        var height: Int?
        
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            width = Int(abs(size.width))
            height = Int(abs(size.height))
        }
        
        return MediaMetadata(
            width: width,
            height: height,
            duration: duration.isFinite ? duration : nil
        )
    }
    
    private static func extractAudioMetadata(from url: URL) -> MediaMetadata {
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        
        return MediaMetadata(duration: duration.isFinite ? duration : nil)
    }
}

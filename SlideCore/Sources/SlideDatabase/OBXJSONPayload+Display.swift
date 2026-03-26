import Foundation

// Public display helpers for payloads, exported from SlideDatabase so other targets can use them
public extension OBXJSONPayload {
    /// Kind-based subtitle (title is now on the entity's displayName column)
    var displayTitle: String {
        kindSubtitle
    }

    var kindEmoji: String {
        switch self {
        case .link: return "🔗"
        case .pdf: return "📄"
        case .note: return "📝"
        case .image: return "🖼️"
        case .video: return "🎬"
        case .audio: return "🎵"
        case .terminal: return "⬛"
        case .codeEditor: return "📝"
        case .group: return "📁"
        case .invalid: return "⚠️"
        }
    }

    var kindSubtitle: String {
        switch self {
        case .link: return "Link"
        case .pdf: return "PDF"
        case .note: return "Note"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .terminal: return "Terminal"
        case .codeEditor: return "Code Editor"
        case .group: return "Collection"
        case .invalid: return "Unavailable"
        }
    }
}

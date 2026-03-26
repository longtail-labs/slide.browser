import Foundation

// MARK: - SomaFM Channel

public struct SomaFMChannel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let genre: String
    public let listeners: Int
    public let imageURL: URL?
    public let playlists: [SomaFMPlaylist]

    public init(id: String, title: String, description: String, genre: String, listeners: Int, imageURL: URL?, playlists: [SomaFMPlaylist]) {
        self.id = id
        self.title = title
        self.description = description
        self.genre = genre
        self.listeners = listeners
        self.imageURL = imageURL
        self.playlists = playlists
    }
}

// MARK: - SomaFM Playlist

public struct SomaFMPlaylist: Equatable, Sendable {
    public let url: URL
    public let format: StreamFormat
    public let quality: StreamQuality

    public init(url: URL, format: StreamFormat, quality: StreamQuality) {
        self.url = url
        self.format = format
        self.quality = quality
    }

    public enum StreamFormat: String, Sendable {
        case aac
        case aacp
        case mp3
    }

    public enum StreamQuality: String, Sendable {
        case highest
        case high
        case low
    }
}

// MARK: - Playback Status

public enum PlaybackStatus: Equatable, Sendable {
    case stopped
    case loading
    case playing
    case paused
    case error(String)
}

// MARK: - Playback Event

public enum PlaybackEvent: Sendable {
    case statusChanged(PlaybackStatus)
    case trackChanged(String)
}

// MARK: - JSON Decoding

struct SomaFMChannelsResponse: Decodable {
    let channels: [SomaFMChannelJSON]
}

struct SomaFMChannelJSON: Decodable {
    let id: String
    let title: String
    let description: String
    let genre: String
    let listeners: String
    let image: String?
    let playlists: [SomaFMPlaylistJSON]

    func toDomain() -> SomaFMChannel {
        SomaFMChannel(
            id: id,
            title: title,
            description: description,
            genre: genre,
            listeners: Int(listeners) ?? 0,
            imageURL: image.flatMap { URL(string: $0) },
            playlists: playlists.compactMap { $0.toDomain() }
        )
    }
}

struct SomaFMPlaylistJSON: Decodable {
    let url: String
    let format: String
    let quality: String

    func toDomain() -> SomaFMPlaylist? {
        guard let playlistURL = URL(string: url),
              let fmt = SomaFMPlaylist.StreamFormat(rawValue: format) else {
            return nil
        }
        let qual: SomaFMPlaylist.StreamQuality
        switch quality {
        case "highest": qual = .highest
        case "high": qual = .high
        default: qual = .low
        }
        return SomaFMPlaylist(url: playlistURL, format: fmt, quality: qual)
    }
}

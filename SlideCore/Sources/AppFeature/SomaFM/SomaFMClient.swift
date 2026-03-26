import Dependencies
import Foundation

// MARK: - SomaFM Client

struct SomaFMClient: Sendable {
    /// Fetch all SomaFM channels, sorted by listener count descending.
    var fetchChannels: @Sendable () async throws -> [SomaFMChannel]

    /// Resolve the actual stream URL from a PLS playlist file.
    var resolveStreamURL: @Sendable (_ playlist: SomaFMPlaylist) async throws -> URL

    /// Start audio playback, returning events for status and metadata changes.
    var play: @Sendable (_ url: URL) async -> AsyncStream<PlaybackEvent>

    /// Pause the current stream.
    var pause: @Sendable () async -> Void

    /// Resume the current stream.
    var resume: @Sendable () async -> Void

    /// Stop playback entirely.
    var stop: @Sendable () async -> Void

    /// Set playback volume (0.0 - 1.0).
    var setVolume: @Sendable (_ volume: Float) async -> Void
}

// MARK: - Live Implementation

extension SomaFMClient: DependencyKey {
    static let liveValue: SomaFMClient = {
        let player = AudioPlayerActor()

        return SomaFMClient(
            fetchChannels: {
                let url = URL(string: "https://somafm.com/channels.json")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(SomaFMChannelsResponse.self, from: data)
                return response.channels
                    .map { $0.toDomain() }
                    .sorted { $0.listeners > $1.listeners }
            },
            resolveStreamURL: { playlist in
                let (data, _) = try await URLSession.shared.data(from: playlist.url)
                guard let content = String(data: data, encoding: .utf8) else {
                    throw SomaFMError.invalidPlaylist
                }
                for line in content.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.lowercased().hasPrefix("file1=") {
                        let urlString = String(trimmed.dropFirst(6))
                        if let streamURL = URL(string: urlString) {
                            return streamURL
                        }
                    }
                }
                throw SomaFMError.noStreamURL
            },
            play: { url in
                await player.play(url: url)
            },
            pause: {
                await player.pause()
            },
            resume: {
                await player.resume()
            },
            stop: {
                await player.stop()
            },
            setVolume: { volume in
                await player.setVolume(volume)
            }
        )
    }()

    static let testValue = SomaFMClient(
        fetchChannels: { [] },
        resolveStreamURL: { _ in URL(string: "https://example.com")! },
        play: { _ in AsyncStream { $0.finish() } },
        pause: {},
        resume: {},
        stop: {},
        setVolume: { _ in }
    )
}

// MARK: - Dependency Registration

extension DependencyValues {
    var somaFMClient: SomaFMClient {
        get { self[SomaFMClient.self] }
        set { self[SomaFMClient.self] = newValue }
    }
}

// MARK: - Errors

enum SomaFMError: LocalizedError {
    case invalidPlaylist
    case noStreamURL

    var errorDescription: String? {
        switch self {
        case .invalidPlaylist: "Could not parse playlist file"
        case .noStreamURL: "No stream URL found in playlist"
        }
    }
}

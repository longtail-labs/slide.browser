import ComposableArchitecture
import Foundation
import Sharing

@Reducer
public struct SomaFMFeature {
    @ObservableState
    public struct State: Equatable {
        public var channels: [SomaFMChannel] = []
        public var selectedChannel: SomaFMChannel?
        public var playbackStatus: PlaybackStatus = .stopped
        public var currentTrackTitle: String?
        public var volume: Float = 0.8
        public var isChannelPickerPresented: Bool = false

        @Shared(.appStorage("somafmLastChannelId")) public var lastChannelId: String?

        public var isPlaying: Bool {
            playbackStatus == .playing
        }

        public init() {}
    }

    public enum Action: Sendable {
        // Lifecycle
        case onAppear
        case channelsLoaded([SomaFMChannel])
        case channelsLoadFailed(String)

        // Channel selection
        case selectChannel(SomaFMChannel)
        case toggleChannelPicker

        // Playback controls
        case togglePlayback
        case play
        case pause
        case skipNext
        case skipPrevious
        case shuffle

        // Playback events from stream
        case playbackEvent(PlaybackEvent)

        // Volume
        case setVolume(Float)

        // Stream resolution
        case streamResolved(URL)
        case streamResolveFailed(String)
    }

    @Dependency(\.somaFMClient) var client

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.channels.isEmpty else { return .none }
                return .run { send in
                    do {
                        let channels = try await client.fetchChannels()
                        await send(.channelsLoaded(channels))
                    } catch {
                        await send(.channelsLoadFailed(error.localizedDescription))
                    }
                }

            case let .channelsLoaded(channels):
                state.channels = channels
                // Restore last channel if available
                if let lastId = state.lastChannelId,
                   let channel = channels.first(where: { $0.id == lastId }) {
                    state.selectedChannel = channel
                }
                return .none

            case .channelsLoadFailed:
                return .none

            case let .selectChannel(channel):
                state.selectedChannel = channel
                state.$lastChannelId.withLock { $0 = channel.id }
                state.isChannelPickerPresented = false
                return .send(.play)

            case .toggleChannelPicker:
                state.isChannelPickerPresented.toggle()
                return .none

            case .togglePlayback:
                switch state.playbackStatus {
                case .playing:
                    return .send(.pause)
                case .paused:
                    return .send(.play)
                case .stopped, .error:
                    return .send(.play)
                case .loading:
                    return .none
                }

            case .play:
                guard let channel = state.selectedChannel,
                      let playlist = channel.playlists.first else {
                    // No channel selected — open picker
                    state.isChannelPickerPresented = true
                    return .none
                }
                state.playbackStatus = .loading
                return .run { send in
                    do {
                        let url = try await client.resolveStreamURL(playlist)
                        await send(.streamResolved(url))
                    } catch {
                        await send(.streamResolveFailed(error.localizedDescription))
                    }
                }

            case let .streamResolved(url):
                return .run { send in
                    let events = await client.play(url)
                    for await event in events {
                        await send(.playbackEvent(event))
                    }
                }

            case let .streamResolveFailed(message):
                state.playbackStatus = .error(message)
                return .none

            case .pause:
                state.playbackStatus = .paused
                return .run { _ in
                    await client.pause()
                }

            case .skipNext:
                guard let current = state.selectedChannel,
                      let idx = state.channels.firstIndex(where: { $0.id == current.id }) else {
                    return .none
                }
                let nextIdx = (idx + 1) % state.channels.count
                return .send(.selectChannel(state.channels[nextIdx]))

            case .skipPrevious:
                guard let current = state.selectedChannel,
                      let idx = state.channels.firstIndex(where: { $0.id == current.id }) else {
                    return .none
                }
                let prevIdx = idx == 0 ? state.channels.count - 1 : idx - 1
                return .send(.selectChannel(state.channels[prevIdx]))

            case .shuffle:
                guard !state.channels.isEmpty else { return .none }
                let random = state.channels.randomElement()!
                return .send(.selectChannel(random))

            case let .playbackEvent(event):
                switch event {
                case let .statusChanged(status):
                    state.playbackStatus = status
                case let .trackChanged(title):
                    state.currentTrackTitle = title
                }
                return .none

            case let .setVolume(volume):
                state.volume = volume
                return .run { _ in
                    await client.setVolume(volume)
                }
            }
        }
    }
}

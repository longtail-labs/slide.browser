import AVFoundation
import Foundation

/// Actor wrapping AVPlayer for SomaFM stream playback.
/// Uses AVPlayerItemMetadataOutput for now-playing info and handles stream errors.
actor AudioPlayerActor {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var metadataDelegate: MetadataDelegate?

    private var eventContinuation: AsyncStream<PlaybackEvent>.Continuation?

    /// Start playing a stream URL, returning an AsyncStream of playback events.
    func play(url: URL) -> AsyncStream<PlaybackEvent> {
        stop()

        let stream = AsyncStream<PlaybackEvent> { continuation in
            self.eventContinuation = continuation
        }

        let item = AVPlayerItem(url: url)
        self.playerItem = item

        // Set up metadata output
        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        let delegate = MetadataDelegate { [weak self] title in
            Task { [weak self] in
                await self?.handleTrackChange(title)
            }
        }
        self.metadataDelegate = delegate
        metadataOutput.setDelegate(delegate, queue: .main)
        item.add(metadataOutput)

        let player = AVPlayer(playerItem: item)
        self.player = player

        eventContinuation?.yield(.statusChanged(.loading))

        // Observe player item status
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { [weak self] in
                await self?.handleStatusChange(item.status, error: item.error)
            }
        }

        player.play()
        return stream
    }

    func pause() {
        player?.pause()
        eventContinuation?.yield(.statusChanged(.paused))
    }

    func resume() {
        player?.play()
        eventContinuation?.yield(.statusChanged(.playing))
    }

    func stop() {
        player?.pause()
        player = nil
        playerItem = nil
        statusObservation?.invalidate()
        statusObservation = nil
        metadataDelegate = nil
        eventContinuation?.yield(.statusChanged(.stopped))
        eventContinuation?.finish()
        eventContinuation = nil
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    // MARK: - Private

    private func handleStatusChange(_ status: AVPlayerItem.Status, error: Error?) {
        switch status {
        case .readyToPlay:
            eventContinuation?.yield(.statusChanged(.playing))
        case .failed:
            let message = error?.localizedDescription ?? "Stream error"
            eventContinuation?.yield(.statusChanged(.error(message)))
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleTrackChange(_ title: String) {
        eventContinuation?.yield(.trackChanged(title))
    }
}

// MARK: - Metadata Delegate

private final class MetadataDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate, Sendable {
    private let onTrackChange: @Sendable (String) -> Void

    init(onTrackChange: @escaping @Sendable (String) -> Void) {
        self.onTrackChange = onTrackChange
        super.init()
    }

    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        for group in groups {
            for item in group.items {
                Task {
                    if let title = try? await item.load(.stringValue), !title.isEmpty {
                        onTrackChange(title)
                        return
                    }
                }
            }
        }
    }
}

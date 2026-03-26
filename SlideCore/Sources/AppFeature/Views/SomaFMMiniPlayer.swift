import ComposableArchitecture
import SwiftUI

/// Compact SomaFM player for the status bar: play/pause + channel name + now-playing.
struct SomaFMMiniPlayer: View {
    let store: StoreOf<SomaFMFeature>

    var body: some View {
        HStack(spacing: 6) {
            // Play/pause button
            Button {
                store.send(.togglePlayback)
            } label: {
                Image(systemName: playbackIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(store.isPlaying ? "Pause" : "Play")

            // Channel name (clickable → popover)
            Button {
                store.send(.toggleChannelPicker)
            } label: {
                HStack(spacing: 4) {
                    if let channel = store.selectedChannel {
                        Text(channel.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if let track = store.currentTrackTitle, store.isPlaying {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.4))

                            MarqueeText(text: track)
                                .frame(maxWidth: 200)
                        }
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("SomaFM")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { store.isChannelPickerPresented },
                set: { _ in store.send(.toggleChannelPicker) }
            ), arrowEdge: .top) {
                ChannelPickerPopover(store: store)
            }

            // Skip buttons (only when playing or paused)
            if store.selectedChannel != nil {
                Button { store.send(.skipPrevious) } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Previous channel")

                Button { store.send(.skipNext) } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Next channel")
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
    }

    private var playbackIcon: String {
        switch store.playbackStatus {
        case .playing: return "pause.fill"
        case .loading: return "ellipsis"
        case .stopped, .paused, .error: return "play.fill"
        }
    }
}

// MARK: - Marquee Text (scrolling track title)

private struct MarqueeText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(.secondary.opacity(0.7))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

// MARK: - Channel Picker Popover

struct ChannelPickerPopover: View {
    let store: StoreOf<SomaFMFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .medium))
                Text("SomaFM Channels")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()

                Button { store.send(.shuffle) } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Random channel")
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Channel list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.channels) { channel in
                        channelRow(channel)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 280)
    }

    private func channelRow(_ channel: SomaFMChannel) -> some View {
        let isSelected = store.selectedChannel?.id == channel.id

        return Button {
            store.send(.selectChannel(channel))
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .lineLimit(1)

                    Text(channel.genre.replacingOccurrences(of: "|", with: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Listener count
                HStack(spacing: 3) {
                    Image(systemName: "headphones")
                        .font(.system(size: 9))
                    Text("\(channel.listeners)")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

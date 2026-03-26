import SwiftUI
import AVKit
import SlideDatabase

struct AudioView: View {
    let object: TaskObject
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?
    
    var body: some View {
        VStack(spacing: 40) {
            // Album art or icon
            Image(systemName: "music.note")
                .font(.system(size: 120))
                .foregroundColor(.secondary)
                .frame(width: 200, height: 200)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(20)
            
            // Title
            Text(object.displayTitle)
                .font(.title)
                .multilineTextAlignment(.center)
            
            // Time info
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $currentTime, in: 0...max(duration, 1)) { editing in
                    if !editing, let player = player {
                        player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1000))
                    }
                }
                
                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            
            // Playback controls
            HStack(spacing: 32) {
                Button(action: skipBackward) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                .buttonStyle(.plain)
                
                Button(action: skipForward) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            
            // File info
            if object.filePath != nil {
                VStack(spacing: 4) {
                    if let originalName = getOriginalFileName() {
                        Text(originalName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let size = getFileSize() {
                        Text(formatFileSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }
    
    private func setupPlayer() {
        guard let filePath = object.filePath else { return }
        
        player = AVPlayer(url: filePath)
        
        // Get duration
        player?.currentItem?.asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak player] in
            guard let item = player?.currentItem else { return }
            DispatchQueue.main.async {
                let duration = CMTimeGetSeconds(item.duration)
                if duration.isFinite {
                    self.duration = duration
                }
            }
        }
        
        // Observe time
        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                self.currentTime = seconds
            }
        }
        
        // Observe play state
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            self.isPlaying = false
            self.currentTime = 0
            self.player?.seek(to: .zero)
        }
    }
    
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }
    
    private func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
    
    private func skipForward() {
        guard let player = player else { return }
        let newTime = min(currentTime + 15, duration)
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 1000))
    }
    
    private func skipBackward() {
        guard let player = player else { return }
        let newTime = max(currentTime - 15, 0)
        player.seek(to: CMTime(seconds: newTime, preferredTimescale: 1000))
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func getOriginalFileName() -> String? {
        switch object.payload {
        case .audio(let data):
            return data.originalFileName
        default:
            return nil
        }
    }
    
    private func getFileSize() -> Int? {
        switch object.payload {
        case .audio(let data):
            return data.size > 0 ? data.size : nil
        default:
            return nil
        }
    }
}
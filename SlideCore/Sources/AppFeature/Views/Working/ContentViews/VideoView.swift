import SwiftUI
import AVKit
import SlideDatabase

struct VideoView: View {
    let object: TaskObject
    @State private var player: AVPlayer?
    
    var body: some View {
        if let filePath = object.filePath {
            VideoPlayer(player: player)
                .onAppear {
                    player = AVPlayer(url: filePath)
                }
                .onDisappear {
                    player?.pause()
                    player = nil
                }
                .background(Color.black)
        } else {
            VStack {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("Video not found")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
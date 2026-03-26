import ComposableArchitecture
import SwiftUI

struct StatusBarView: View {
    let store: StoreOf<SlideAppFeature>

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left: SomaFM mini-player
            SomaFMMiniPlayer(store: store.scope(state: \.somaFM, action: \.somaFM))

            Spacer()

            // Right: Version
            Text("v\(appVersion)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

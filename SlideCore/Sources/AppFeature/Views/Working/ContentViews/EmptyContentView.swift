import SwiftUI

struct EmptyContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "safari")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Select a tab to start browsing")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
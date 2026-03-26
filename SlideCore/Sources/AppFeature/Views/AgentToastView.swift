import SwiftUI

/// Bottom-right toast for agent notifications with an optional "Go to" action.
struct AgentToastView: View {
    let title: String
    var message: String? = nil
    var hasGoTo: Bool = false
    var onGoTo: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: "terminal")
                .font(.system(size: 14))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            if hasGoTo {
                Divider()
                    .frame(height: 24)

                Button(action: { onGoTo?() }) {
                    Text("Go to")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .frame(maxWidth: 320)
    }
}

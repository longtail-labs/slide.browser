import ComposableArchitecture
import SlideDatabase
import SwiftUI

extension Notification.Name {
    static let focusFilterBar = Notification.Name("FocusFilterBar")
}

struct FilterBarView: View {
    @Bindable var store: StoreOf<ContentBrowserFeature>
    let onToggleCommandBar: () -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Hamburger menu
            Button(action: { store.send(.toggleSidebar) }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .pointerHandCursor()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Filter, paste a URL, or use /note", text: Binding(
                    get: { store.searchQuery },
                    set: { store.send(.setSearchQuery($0)) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFocused)
                .onSubmit {
                    store.send(.submitSearchQuery)
                }

                if let submitHint {
                    HStack(spacing: 4) {
                        Text("↩")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        Text(submitHint)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }

                if !store.searchQuery.isEmpty {
                    Button(action: { store.send(.setSearchQuery("")) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )

            // Command palette button
            Button(action: onToggleCommandBar) {
                HStack(spacing: 2) {
                    Image(systemName: "command")
                        .font(.system(size: 10, weight: .medium))
                    Text("K")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .pointerHandCursor()
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .onReceive(NotificationCenter.default.publisher(for: .focusFilterBar)) { _ in
            isSearchFocused = true
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var submitHint: String? {
        switch SlideQuickInputParser.action(for: store.searchQuery) {
        case .openURL:
            return "open"
        case .createNote:
            return "new note"
        case .createTerminal:
            return "new terminal"
        case .filter:
            return nil
        }
    }
}

#Preview("Filter Bar – URL") {
    FilterBarView(
        store: Store(
            initialState: {
                var state = ContentBrowserFeature.State()
                state.searchQuery = "docs.swift.org"
                return state
            }()
        ) {
            ContentBrowserFeature()
        },
        onToggleCommandBar: {}
    )
    .frame(width: 900)
}

import ComposableArchitecture
import SwiftUI

@Reducer
public struct SettingsFeature {
    @ObservableState
    public struct State: Equatable {
        public var selected: Section

        public init(selected: Section = .keys) {
            self.selected = selected
        }
    }

    public enum Section: String, CaseIterable, Equatable, Sendable, Identifiable {
        case keys = "Keys"
        case contact = "Contact"
        case mcp = "MCP"
        case privacy = "Privacy"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .keys: return "keyboard"
            case .contact: return "person.crop.circle"
            case .mcp: return "shippingbox"
            case .privacy: return "lock.shield"
            }
        }
    }

    public enum Action: Sendable, Equatable {
        case select(Section)
        case dismiss
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .select(section):
                state.selected = section
                return .none
            case .dismiss:
                return .none
            }
        }
    }
}

// MARK: - View

public struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                List(SettingsFeature.Section.allCases, id: \.self, selection: Binding(
                    get: { store.selected },
                    set: { store.send(.select($0)) }
                )) { section in
                    HStack(spacing: 8) {
                        Image(systemName: section.iconName)
                        Text(section.rawValue)
                    }
                    .tag(section)
                }
                .listStyle(.sidebar)
                .frame(width: 180)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 16) {
                switch store.selected {
                case .keys:
                    SettingsSection(title: "Keyboard Shortcuts") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⌘K — Toggle Command Bar")
                            Text("⌘\\ — Toggle Right Sidebar")
                            Text("⌘L — Focus Filter Bar")
                            Text("⌘T — New Tab")
                            Text("⌘W — Close Panel")
                            Text("⌘⇧⌫ — Exit Task")
                            Text("⌘F — Find on Page")
                            Text("⌘⌥↑/↓ — Previous/Next Object")
                            Text("⌘R — Reload")
                            Text("⌘[ / ⌘] — Back/Forward")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                case .contact:
                    SettingsSection(title: "Contact") {
                        Text("Contact settings placeholder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                case .mcp:
                    SettingsSection(title: "MCP") {
                        Text("Model Context Protocol settings placeholder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                case .privacy:
                    SettingsSection(title: "Privacy") {
                        Text("Privacy settings placeholder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("Done") { store.send(.dismiss) }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 520, minHeight: 420)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3).bold()
            content
        }
    }
}

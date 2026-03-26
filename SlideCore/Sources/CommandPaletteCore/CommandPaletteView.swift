import SwiftUI
import ComposableArchitecture
import Kingfisher

public struct CommandPaletteView: View {
    @Bindable var store: StoreOf<CommandPaletteFeature>
    @FocusState private var focused: Bool
    @State private var keyboardNavToken: Int = 0

    public init(store: StoreOf<CommandPaletteFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { store.send(.close) }

            VStack(spacing: 0) {
                if store.panes.count > 1 || store.context.scopeProjectName != nil {
                    HStack(spacing: 8) {
                        if store.panes.count > 1 {
                            BreadcrumbView(
                                crumbs: store.panes.map { $0.title },
                                onTap: { index in
                                    let pops = max(0, store.panes.count - 1 - index)
                                    if pops > 0 { (0..<pops).forEach { _ in store.send(.popPane) } }
                                }
                            )
                        }
                        Spacer()
                        if let projectName = store.context.scopeProjectName {
                            ProjectScopeChip(name: projectName) {
                                store.send(.clearProjectScope)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    Divider()
                }
                header
                Divider()
                content
                footer
            }
            .frame(width: 680)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 24)
            .onAppear { focused = true }
        }
        // Keyboard at container level so arrows work while focusing TextField
        .onKeyPress(.downArrow) {
            if let idx = store.currentPaneIndex { store.send(.moveSelection(paneIndex: idx, delta: 1)); keyboardNavToken &+= 1; return .handled }
            return .ignored
        }
        .onKeyPress(.upArrow) {
            if let idx = store.currentPaneIndex { store.send(.moveSelection(paneIndex: idx, delta: -1)); keyboardNavToken &+= 1; return .handled }
            return .ignored
        }
        .onKeyPress(.return) { 
            if store.isInputMode {
                store.send(.submitInputPane)
            } else {
                submitSelectedIfPossible()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            if store.closeOnFirstEscape && store.panes.count > 1 {
                store.send(.close)
                return .handled
            }
            if (store.panes.count > 1) { store.send(.popPane); return .handled }
            store.send(.close)
            return .handled
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholderText, text: $store.query.sending(\.setQuery))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { 
                        if store.isInputMode {
                            store.send(.submitInputPane)
                        } else {
                            submitSelectedIfPossible()
                        }
                    }
                if !store.query.isEmpty {
                    Button(action: { store.send(.setQuery("")) }) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: { store.send(.close) }) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
    
    private var placeholderText: String {
        if let inputSpec = store.currentInputSpec {
            return inputSpec.spec.placeholder
        }
        return "Type a command…"
    }

    @ViewBuilder
    private var content: some View {
        if let paneIndex = store.currentPaneIndex {
            let pane = store.panes[paneIndex]
            switch pane.kind {
            case .list:
                PaletteCommandListView(
                    paneIndex: paneIndex,
                    items: pane.items,
                    selectedIndex: pane.selectedIndex,
                    keyboardNavToken: keyboardNavToken,
                    onHoverIndex: { idx in store.send(.setSelection(paneIndex: paneIndex, index: idx)) },
                    onSelectItem: { id in store.send(.selectItem(paneIndex: paneIndex, itemID: id)) },
                    onMove: { delta in store.send(.moveSelection(paneIndex: paneIndex, delta: delta)) }
                )
                .frame(height: 360)
            case .input(let spec, _):
                // Show a simple instruction instead of another input field
                VStack(alignment: .center, spacing: 12) {
                    Spacer()
                    Text(spec.title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Press Return to save")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
            }
        } else {
            Color.clear.frame(height: 360)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 16) {
                Label("Navigate", systemImage: "arrow.up.arrow.down")
                Label("Select", systemImage: "return")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            Spacer()
            Text("ESC to close")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func submitSelectedIfPossible() {
        if let idx = store.currentPaneIndex {
            let pane = store.panes[idx]
            guard !pane.items.isEmpty else { return }
            let selected = pane.items[min(max(pane.selectedIndex, 0), pane.items.count - 1)]
            store.send(.selectItem(paneIndex: idx, itemID: selected.id))
        }
    }

}

// MARK: - Nicer, hover-aware list like CommandBarCore

private struct SelectedRectPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct PaletteCommandListView: View {
    let paneIndex: Int
    let items: [CommandItem]
    let selectedIndex: Int
    let keyboardNavToken: Int
    let onHoverIndex: (Int) -> Void
    let onSelectItem: (String) -> Void
    let onMove: (Int) -> Void

    @State private var hoverEnabled = false
    @State private var initialMouse: CGPoint = .zero
    @State private var initialSet = false
    @State private var mouseHasMoved = false
    @State private var viewportHeight: CGFloat = 0
    @State private var selectedRect: CGRect?

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { outerGeo in
                let height = outerGeo.size.height
                Color.clear.onAppear { viewportHeight = height }
                ScrollView {
                    // Use VStack for smaller lists, LazyVStack for larger ones
                    Group {
                        if items.count <= 20 {
                            VStack(spacing: 6) {
                                ForEach(items.indices, id: \.self) { idx in
                                    let item = items[idx]
                                    PaletteCommandRow(
                                        item: item,
                                        isSelected: idx == selectedIndex,
                                        onTap: { onSelectItem(item.id) },
                                        onHover: {
                                            if hoverEnabled && mouseHasMoved { onHoverIndex(idx) }
                                        }
                                    )
                                    .id(item.id)
                                    // Only add geometry reader for selected item to reduce overhead
                                    .background(
                                        idx == selectedIndex ?
                                        GeometryReader { rowGeo in
                                            Color.clear.preference(key: SelectedRectPreferenceKey.self, value: rowGeo.frame(in: .named("paletteScroll")))
                                        } : nil
                                    )
                                }
                            }
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(items.indices, id: \.self) { idx in
                                    let item = items[idx]
                                    PaletteCommandRow(
                                        item: item,
                                        isSelected: idx == selectedIndex,
                                        onTap: { onSelectItem(item.id) },
                                        onHover: {
                                            if hoverEnabled && mouseHasMoved { onHoverIndex(idx) }
                                        }
                                    )
                                    .id(item.id)
                                    // Only add geometry reader for selected item to reduce overhead
                                    .background(
                                        idx == selectedIndex ?
                                        GeometryReader { rowGeo in
                                            Color.clear.preference(key: SelectedRectPreferenceKey.self, value: rowGeo.frame(in: .named("paletteScroll")))
                                        } : nil
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                .coordinateSpace(name: "paletteScroll")
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    if !hoverEnabled { break }
                    if !initialSet { initialMouse = loc; initialSet = true }
                    let dx = loc.x - initialMouse.x
                    let dy = loc.y - initialMouse.y
                    if hypot(dx, dy) > 10 { mouseHasMoved = true }
                case .ended:
                    break
                }
            }
            .onAppear {
                mouseHasMoved = false
                hoverEnabled = false
                initialSet = false
                // Start tracking after a very short delay to avoid initial accidental selection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { hoverEnabled = true }
            }
            .onPreferenceChange(SelectedRectPreferenceKey.self) { rect in selectedRect = rect }
            // Scroll only when keyboard nav happens and selection is offscreen
            .onChange(of: keyboardNavToken) { _, _ in
                guard items.indices.contains(selectedIndex) else { return }
                guard let rect = selectedRect else {
                    // If we lack metrics, scroll to make item visible with padding
                    withAnimation(.easeInOut(duration: 0.12)) { 
                        proxy.scrollTo(items[selectedIndex].id, anchor: UnitPoint(x: 0.5, y: 0.3))
                    }
                    return
                }
                
                // Add padding to ensure next/previous items are visible
                let padding: CGFloat = 40
                
                // Item is above visible area
                if rect.minY < padding {
                    withAnimation(.easeInOut(duration: 0.12)) { 
                        // Scroll just enough to bring item into view with padding at top
                        proxy.scrollTo(items[selectedIndex].id, anchor: UnitPoint(x: 0.5, y: 0.15))
                    }
                } 
                // Item is below visible area
                else if rect.maxY > viewportHeight - padding {
                    withAnimation(.easeInOut(duration: 0.12)) { 
                        // Scroll just enough to bring item into view with padding at bottom
                        proxy.scrollTo(items[selectedIndex].id, anchor: UnitPoint(x: 0.5, y: 0.85))
                    }
                }
                // Item is already visible - no scrolling needed
            }
        }
    }
}

private struct PaletteCommandRow: View {
    let item: CommandItem
    let isSelected: Bool
    let onTap: () -> Void
    let onHover: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PaletteIconView(icon: item.icon, isSelected: isSelected)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let meta = item.metadata, !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(isSelected ? Color.white.opacity(0.15) : Color(nsColor: .separatorColor).opacity(0.2))
                    )
            }
            if case .pushPane = item.transition {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            } else if case .pushStaticList = item.transition {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { inside in if inside { onHover() } }
    }
}

// MARK: - Breadcrumb View

private struct BreadcrumbView: View {
    let crumbs: [String]
    let onTap: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { idx, title in
                Button(action: { onTap(idx) }) {
                    Text(title)
                        .font(.system(size: 12, weight: idx == crumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(idx == crumbs.count - 1 ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                if idx < crumbs.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }
}

private struct ProjectScopeChip: View {
    let name: String
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.15))
        )
    }
}

private struct PaletteIconView: View {
    let icon: String?
    let isSelected: Bool
    var body: some View {
        if let icon {
            // Remote image URL
            if icon.hasPrefix("http://") || icon.hasPrefix("https://") {
                KFImage.url(URL(string: icon))
                    .placeholder {
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? .white : .secondary)
                    }
                    .onFailure { _ in
                        // On failure, Kingfisher will show placeholder
                    }
                    .loadDiskFileSynchronously() // Avoid flickering for cached images  
                    .fade(duration: 0.1) // Quick fade in
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            // Asset name with explicit prefix
            else if icon.hasPrefix("asset:") {
                let name = String(icon.dropFirst("asset:".count))
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            // Emoji
            else if icon.count == 1, let scalar = icon.unicodeScalars.first, scalar.properties.isEmoji {
                Text(icon).font(.system(size: 18))
            }
            // Try system symbol first, then fallback to asset by name
            else {
                // SF Symbol
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
        } else {
            Image(systemName: "circle.fill").opacity(0)
        }
    }
}

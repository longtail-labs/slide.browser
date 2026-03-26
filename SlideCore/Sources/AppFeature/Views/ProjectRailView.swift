import ComposableArchitecture
import EmojiKit
import SlideDatabase
import SwiftUI

// MARK: - Project Rail View (Discord-style vertical strip)

struct ProjectRailView: View {
    let store: StoreOf<ContentBrowserFeature>
    @State private var hoveredProjectId: UUID?
    @State private var showCreateSheet = false
    @State private var editingProject: OBXProject?
    @State private var draggedProject: OBXProject?
    @State private var dropTargetProjectId: UUID?

    private let railWidth: CGFloat = 56
    private let iconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            // Top spacer to clear macOS traffic lights
            Spacer()
                .frame(height: 38)

            // Scratchpad (always first — like Discord's home button)
            if let scratchpad = store.projects.first(where: { $0.uuid == scratchpadProjectUUID }) {
                scratchpadButton(scratchpad)

                // Separator line (like Discord's divider between home and servers)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(NSColor.separatorColor).opacity(0.4))
                    .frame(width: 24, height: 2)
                    .padding(.vertical, 6)
            }

            // Scrollable project list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(store.projects.filter { $0.uuid != scratchpadProjectUUID }.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.uuid) { project in
                        projectButton(project)
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            // Add project button
            addProjectButton
                .padding(.bottom, 10)
        }
        .frame(width: railWidth)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .sheet(isPresented: $showCreateSheet) {
            ProjectSheet(store: store, isPresented: $showCreateSheet)
        }
        .sheet(item: $editingProject) { project in
            ProjectSheet(store: store, isPresented: Binding(
                get: { editingProject != nil },
                set: { if !$0 { editingProject = nil } }
            ), editing: project)
        }
    }

    // MARK: - Scratchpad

    private func scratchpadButton(_ scratchpad: OBXProject) -> some View {
        let isActive = store.activeProjectId == scratchpad.uuidValue
        let isHover = hoveredProjectId == scratchpad.uuidValue
        let projectActivity = aggregateActivity(for: scratchpad.uuidValue)
        let projectBadge = aggregateBadge(for: scratchpad.uuidValue)

        return RailIconButton(
            emoji: scratchpad.icon,
            colorHex: scratchpad.colorHex,
            isSelected: isActive,
            isHovered: isHover,
            activityState: projectActivity,
            badgeCount: projectBadge,
            railWidth: railWidth,
            iconSize: iconSize
        )
        .onTapGesture { store.send(.selectProject(scratchpad.uuidValue)) }
        .onHover { hoveredProjectId = $0 ? scratchpad.uuidValue : nil }
        .help("All Objects")
        .dropDestination(for: String.self) { items, _ in
            guard let uuid = items.first.flatMap(UUID.init(uuidString:)),
                  let spUUID = UUID(uuidString: scratchpadProjectUUID) else { return false }
            // Ignore project drops — scratchpad only accepts object drops
            if store.projects.contains(where: { $0.uuidValue == uuid }) { return false }
            store.send(.moveObjectToProject(uuid, spUUID))
            return true
        }
    }

    // MARK: - Project

    private func projectButton(_ project: OBXProject) -> some View {
        let isActive = store.activeProjectId == project.uuidValue
        let isHover = hoveredProjectId == project.uuidValue
        let projectActivity = aggregateActivity(for: project.uuidValue)
        let projectBadge = aggregateBadge(for: project.uuidValue)

        return RailIconButton(
            emoji: project.icon,
            colorHex: project.colorHex,
            isSelected: isActive,
            isHovered: isHover,
            activityState: projectActivity,
            badgeCount: projectBadge,
            railWidth: railWidth,
            iconSize: iconSize
        )
        .onTapGesture {
            store.send(.selectProject(project.uuidValue))
        }
        .onHover { hoveredProjectId = $0 ? project.uuidValue : nil }
        .help(project.name)
        .contextMenu {
            Button("Edit...") {
                editingProject = project
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.send(.deleteProject(project.uuidValue))
            }
        }
        .onDrag {
            draggedProject = project
            return NSItemProvider(object: project.uuid as NSString)
        }
        .dropDestination(for: String.self) { items, _ in
            defer { draggedProject = nil; dropTargetProjectId = nil }
            guard let uuidString = items.first,
                  let uuid = UUID(uuidString: uuidString) else { return false }
            // Project reorder
            if store.projects.contains(where: { $0.uuidValue == uuid && $0.uuid != scratchpadProjectUUID }) {
                var ordered = store.projects
                    .filter { $0.uuid != scratchpadProjectUUID }
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map { $0.uuidValue }
                guard let fromIndex = ordered.firstIndex(of: uuid),
                      let toIndex = ordered.firstIndex(of: project.uuidValue),
                      fromIndex != toIndex else { return false }
                let item = ordered.remove(at: fromIndex)
                ordered.insert(item, at: toIndex)
                store.send(.reorderProjects(ordered))
                return true
            }
            // Object → project move
            store.send(.moveObjectToProject(uuid, project.uuidValue))
            return true
        } isTargeted: { targeted in
            dropTargetProjectId = targeted ? project.uuidValue : nil
        }
        .opacity(draggedProject?.uuid == project.uuid ? 0.4 : 1.0)
        .overlay(alignment: .top) {
            if dropTargetProjectId == project.uuidValue,
               let dragged = draggedProject,
               dragged.uuidValue != project.uuidValue {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 3)
                    .offset(y: -4)
            }
        }
    }

    // MARK: - Activity Aggregation

    private func aggregateActivity(for projectId: UUID) -> ObjectActivityState {
        let objectsInProject = store.objects.filter { $0.projectId == projectId }
        for obj in objectsInProject {
            if let state = store.activityStates[obj.uuidValue] {
                if state == .attention { return .attention }
                if state == .active { return .active }
            }
        }
        return .idle
    }

    private func aggregateBadge(for projectId: UUID) -> Int {
        let objectsInProject = store.objects.filter { $0.projectId == projectId }
        return objectsInProject.reduce(0) { sum, obj in
            sum + (store.badgeCounts[obj.uuidValue] ?? 0)
        }
    }

    // MARK: - Add Button

    private var addProjectButton: some View {
        Button { showCreateSheet = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: iconSize / 2)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: iconSize, height: iconSize)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.green)
            }
        }
        .buttonStyle(.plain)
        .pointerHandCursor()
    }
}

// MARK: - Rail Icon (Discord-style squircle with color)

private struct RailIconButton: View {
    let emoji: String
    let colorHex: String
    let isSelected: Bool
    let isHovered: Bool
    var activityState: ObjectActivityState = .idle
    var badgeCount: Int = 0
    let railWidth: CGFloat
    let iconSize: CGFloat

    @State private var isPulsing = false

    private var color: Color { Color(hex: colorHex) ?? .gray }
    // Discord: circle (50%) when idle, squircle (~35%) on hover/selected
    private var cornerRadius: CGFloat {
        isSelected || isHovered ? iconSize * 0.35 : iconSize / 2
    }

    private var activityColor: Color {
        activityState == .attention ? .orange : .blue
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left pill indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? Color.white : (isHovered ? Color.white.opacity(0.5) : Color.clear))
                .frame(width: 3, height: isSelected ? 28 : (isHovered ? 16 : 0))
                .animation(.easeInOut(duration: 0.12), value: isSelected)
                .animation(.easeInOut(duration: 0.12), value: isHovered)

            Spacer(minLength: 0)

            // Squircle icon — morphs from circle to rounded square on hover/select
            ZStack {
                // Pulsing ring for activity
                if activityState != .idle {
                    RoundedRectangle(cornerRadius: cornerRadius + 3)
                        .stroke(activityColor, lineWidth: 2)
                        .frame(width: iconSize + 6, height: iconSize + 6)
                        .opacity(isPulsing ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                        .onAppear { isPulsing = true }
                }

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color.opacity(isSelected ? 1.0 : 0.6))
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: isSelected ? color.opacity(0.4) : .clear, radius: 4, y: 2)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)

                // Emoji
                Text(emoji)
                    .font(.system(size: 18))

                // Badge
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .fixedSize()
                        .offset(x: iconSize / 2 - 4, y: -(iconSize / 2 - 4))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: railWidth, height: iconSize + 6)
        .contentShape(Rectangle())
        .onChange(of: activityState) { _, newState in
            isPulsing = newState != .idle
        }
    }
}

// MARK: - Project Sheet (Create / Edit)

private struct ProjectSheet: View {
    let store: StoreOf<ContentBrowserFeature>
    @Binding var isPresented: Bool
    var editing: OBXProject? = nil

    @State private var name = ""
    @State private var selectedEmoji = "📁"
    @State private var selectedColor: Color = .indigo
    @State private var emojiCategory: EmojiCategory? = .smileysAndPeople
    @State private var emojiSelection: Emoji.GridSelection? = Emoji.GridSelection()
    @State private var emojiQuery = ""

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Project" : "New Project")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            VStack(spacing: 14) {
                // Preview + Color picker row
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(selectedColor)
                            .frame(width: 56, height: 56)
                            .shadow(color: selectedColor.opacity(0.35), radius: 6, y: 3)

                        Text(selectedEmoji)
                            .font(.system(size: 26))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Project name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .onSubmit { submit() }

                        HStack(spacing: 8) {
                            ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 24, height: 24)
                            Text("Project color")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)

                // Emoji picker
                VStack(alignment: .leading, spacing: 5) {
                    Text("ICON")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    // Search field
                    TextField("Search emoji...", text: $emojiQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    // EmojiKit grid
                    ScrollView {
                        EmojiGrid(
                            category: $emojiCategory,
                            selection: $emojiSelection,
                            query: emojiQuery,
                            action: { emoji in
                                selectedEmoji = emoji.char
                            },
                            sectionTitle: { params in
                                params.view
                            },
                            gridItem: { params in
                                params.view
                            }
                        )
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Footer
            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Create Project") { submit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if let project = editing {
                name = project.name
                selectedEmoji = project.icon
                selectedColor = Color(hex: project.colorHex) ?? .indigo
            }
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let hex = selectedColor.toHex()

        if let project = editing {
            // Update existing project
            project.name = trimmed
            project.icon = selectedEmoji
            project.colorHex = hex
            project.updatedAt = Date()
            store.send(.updateProject(project))
        } else {
            // Create new project
            store.send(.createProject(trimmed, selectedEmoji, hex))
        }
        isPresented = false
    }
}

// MARK: - Color → Hex Extension

extension Color {
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return "#6366F1" }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Hex Color Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else { return nil }
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)
        self.init(
            red: Double((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: Double((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgbValue & 0x0000FF) / 255.0
        )
    }
}

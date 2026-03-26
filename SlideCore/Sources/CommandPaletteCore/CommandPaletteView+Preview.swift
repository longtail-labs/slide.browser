import SwiftUI
import ComposableArchitecture

#if DEBUG
struct CommandPalettePreviewContainer: View {
    @State private var isPresented = true
    let store: StoreOf<CommandPaletteFeature>

    init() {
        let store = Store(initialState: CommandPaletteFeature.State()) {
            CommandPaletteFeature()
        } withDependencies: { values in
            let registry = CommandRegistry()
            registry.register(commands: SamplePaletteCommands.definitions())
            registry.registerProvider(id: "tasks", provider: TasksProvider())
            registry.registerProvider(id: "google", provider: GoogleProvider())
            registry.registerProvider(id: "objects", provider: ObjectsProvider())
            registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
            // EmojiProvider removed
            values.commandRegistry = registry
        }
        self.store = store
    }

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            Text("CommandPaletteCore Preview").font(.title2)
        }
        .frame(width: 900, height: 600)
        .onAppear { store.send(.open(scope: .cmdK, preselect: nil)) }
        .overlay {
            if store.isPresented {
                CommandPaletteView(store: store)
            }
        }
    }
}

#Preview("Palette – Cmd+K") {
    CommandPalettePreviewContainer()
}

#Preview("Palette – Cmd+L (web)") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "google", provider: GoogleProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        values.commandRegistry = registry
    }
    ZStack {
        Color(NSColor.windowBackgroundColor)
    }
    .frame(width: 900, height: 600)
    .onAppear { store.send(.open(scope: .cmdL, preselect: nil)) }
    .overlay { CommandPaletteView(store: store) }
}

#Preview("Palette – Cmd+L (with URL)") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "google", provider: GoogleProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        values.commandRegistry = registry
    }
    ZStack {
        Color(NSColor.windowBackgroundColor)
        Text("Cmd-L with pre-filled URL")
    }
    .frame(width: 900, height: 600)
    .onAppear { 
        store.send(.open(scope: .cmdL, preselect: nil, initialQuery: "https://github.com/objectbox/objectbox-swift")) 
    }
    .overlay { CommandPaletteView(store: store) }
}

#Preview("Palette – Preselect Tasks") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        values.commandRegistry = registry
    }
    ZStack { Color(NSColor.windowBackgroundColor) }
        .frame(width: 900, height: 600)
        .onAppear { store.send(.open(scope: .cmdP, preselect: CommandID("viewTasks"))) }
        .overlay { CommandPaletteView(store: store) }
}

#Preview("Palette – Cmd+Shift+P (Tasks)") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        values.commandRegistry = registry
    }
    ZStack { Color(NSColor.windowBackgroundColor) }
        .frame(width: 900, height: 600)
        .onAppear { store.send(.open(scope: .cmdShiftP, preselect: CommandID("viewTasks"))) }
        .overlay { CommandPaletteView(store: store) }
}

#Preview("Palette – Cmd+P (Objects)") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "google", provider: GoogleProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        values.commandRegistry = registry
    }
    ZStack { Color(NSColor.windowBackgroundColor) }
        .frame(width: 900, height: 600)
        .onAppear { store.send(.open(scope: .cmdP, preselect: CommandID("viewObjects"))) }
        .overlay { CommandPaletteView(store: store) }
}

#Preview("Palette – Cmd+T (New Tab Links)") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "google", provider: GoogleProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        values.commandRegistry = registry
    }
    ZStack { Color(NSColor.windowBackgroundColor) }
        .frame(width: 900, height: 600)
        .onAppear { store.send(.open(scope: .cmdT, preselect: CommandID("quickLinks"))) }
        .overlay { CommandPaletteView(store: store) }
}

#Preview("Palette – Cmd+K (Actions + Emoji)") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "google", provider: GoogleProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        values.commandRegistry = registry
    }
    ZStack { Color(NSColor.windowBackgroundColor) }
        .frame(width: 900, height: 600)
        .onAppear { store.send(.open(scope: .cmdK, preselect: CommandID("emojiPicker"))) }
        .overlay { CommandPaletteView(store: store) }
}

#Preview("Palette – Long List + Subcommands") {
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        values.commandRegistry = registry
    }
    ZStack { 
        Color(NSColor.windowBackgroundColor)
        VStack {
            Text("Test the Rename Task flow:")
                .font(.headline)
            Text("1. Select a task")
            Text("2. Choose 'Rename Task'")
            Text("3. Edit the name in the search field")
            Text("4. Press Return to save")
            Text("Check console for delegate effects")
        }
        .foregroundColor(.secondary)
    }
    .frame(width: 900, height: 600)
    .onAppear { store.send(.open(scope: .cmdP, preselect: CommandID("viewTasks"))) }
    .overlay { CommandPaletteView(store: store) }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandPaletteEffect"))) { notification in
        if let effect = notification.object as? CommandEffect {
            print("[Preview] Received effect: \(effect)")
        }
    }
}
#Preview("Palette – Test Rename Task") {
    @State var taskName = "Original Task Name"
    
    let store = Store(initialState: CommandPaletteFeature.State()) {
        CommandPaletteFeature()
    } withDependencies: { values in
        let registry = CommandRegistry()
        registry.register(commands: SamplePaletteCommands.definitions())
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        values.commandRegistry = registry
    }
    
    ZStack { 
        Color(NSColor.windowBackgroundColor)
        VStack(spacing: 20) {
            Text("Current Task Name:")
                .font(.headline)
            Text(taskName)
                .font(.title2)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            Text("Instructions:")
                .font(.headline)
                .padding(.top)
            VStack(alignment: .leading) {
                Text("1. Select any task from the list")
                Text("2. Choose 'Rename Task'")
                Text("3. The current name appears in the search field")
                Text("4. Edit it and press Return")
                Text("5. Watch the console for the effect")
            }
            .font(.system(size: 14))
            .foregroundColor(.secondary)
        }
    }
    .frame(width: 900, height: 600)
    .onAppear { 
        store.send(.open(scope: .cmdP, preselect: CommandID("viewTasks"))) 
    }
    .overlay { 
        CommandPaletteView(store: store)
    }
}

#endif

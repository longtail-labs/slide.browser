import ComposableArchitecture
import Foundation

// MARK: - Example Parent Feature Integration

/// This shows how a parent feature would integrate CommandPaletteCore
/// and handle the delegate actions for things like renaming tasks
@Reducer
public struct ExampleAppFeature {
    @ObservableState
    public struct State {
        public var currentTaskName: String = "My Task"
        public var currentObjectURL: String? = "https://github.com/example/repo"
        
        @Presents public var commandPalette: CommandPaletteFeature.State?
        
        public init() {}
    }
    
    public enum Action {
        case openCommandPalette
        case openCommandPaletteWithURL
        case commandPalette(PresentationAction<CommandPaletteFeature.Action>)
    }
    
    @Dependency(\.commandRegistry) var registry
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .openCommandPalette:
                state.commandPalette = CommandPaletteFeature.State()
                return .send(.commandPalette(.presented(.open(scope: .cmdK, preselect: nil))))
                
            case .openCommandPaletteWithURL:
                // Example: cmd-L opens with current URL pre-filled
                state.commandPalette = CommandPaletteFeature.State()
                let url = state.currentObjectURL ?? ""
                return .send(.commandPalette(.presented(.open(scope: .cmdL, preselect: nil, initialQuery: url))))
                
            case .commandPalette(.presented(.delegate(let delegateAction))):
                switch delegateAction {
                case .effectTriggered(let effect):
                    return handleCommandEffect(effect, state: &state)
                case .didClose:
                    state.commandPalette = nil
                    return .none
                }
                
            case .commandPalette:
                return .none
            }
        }
        .ifLet(\.$commandPalette, action: \.commandPalette) {
            CommandPaletteFeature()
        }
    }
    
    private func handleCommandEffect(_ effect: CommandEffect, state: inout State) -> EffectOf<Self> {
        switch effect {
        case .openURL(let url):
            print("[ExampleApp] Opening URL: \(url)")
            // Actually open the URL
            return .none
            
        case .updateCurrentURL(let url):
            print("[ExampleApp] Updating current URL to: \(url)")
            state.currentObjectURL = url
            return .none
            
        case .selectTask(let taskId):
            print("[ExampleApp] Selecting task: \(taskId)")
            // Navigate to task
            return .none
            
        case .openTask(let taskId):
            print("[ExampleApp] Opening task: \(taskId)")
            // Open task in workspace
            return .none
            
        case .showSettings:
            print("[ExampleApp] Showing settings")
            // Show settings
            return .none
            
        case .toggleDarkMode:
            print("[ExampleApp] Toggling dark mode")
            // Toggle dark mode
            return .none
            
        case .custom(let actionKey, let payload):
            print("[ExampleApp] Custom action: \(actionKey), payload: \(payload)")
            
            // Handle rename task action
            if actionKey.starts(with: "task.rename.") {
                if let newName = payload["value"] {
                    let taskId = String(actionKey.dropFirst("task.rename.".count))
                    print("[ExampleApp] Renaming task \(taskId) to: \(newName)")
                    state.currentTaskName = newName
                    
                    // TODO: Update database
                    // await database.renameTask(taskId, to: newName)
                }
            }
            
            // Handle emoji selection
            else if actionKey.starts(with: "emoji.select") {
                if let emoji = payload["emoji"] {
                    print("[ExampleApp] Selected emoji: \(emoji)")
                    // Update task emoji
                }
            }
            
            return .none
        }
    }
}

// MARK: - Example Setup

public extension ExampleAppFeature {
    static func setupCommandRegistry() -> CommandRegistry {
        let registry = CommandRegistry()
        
        // Register sample commands
        registry.register(commands: SamplePaletteCommands.definitions())
        
        // Register providers
        registry.registerProvider(id: "tasks", provider: TasksProvider())
        registry.registerProvider(id: "google", provider: GoogleProvider())
        registry.registerProvider(id: "objects", provider: ObjectsProvider())
        registry.registerProvider(id: "quicklinks", provider: QuickLinksProvider())
        // EmojiProvider removed
        
        return registry
    }
}
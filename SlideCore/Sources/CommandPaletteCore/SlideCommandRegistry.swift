import Foundation
import Dependencies
import SlideDatabase

// MARK: - Slide Command Registry Setup

public extension CommandRegistry {

    /// Set up the command registry with all Slide app commands and providers
    static func setupForSlide() -> CommandRegistry {
        let registry = CommandRegistry()

        // Register all command definitions
        registry.register(commands: SlideCommands.all())
        print("[CommandRegistry] Registered \(SlideCommands.all().count) commands")

        // Register providers
        registry.registerProvider(id: "slide.objects", provider: SlideAllObjectsProvider())
        registry.registerProvider(id: "slide.quicklinks", provider: SlideQuickLinksProvider())
        registry.registerProvider(id: "slide.websearch", provider: SlideWebSearchProvider())
        registry.registerProvider(id: "slide.moveToProject", provider: SlideMoveToProjectProvider())
        print("[CommandRegistry] Registered 4 providers: slide.objects, slide.quicklinks, slide.websearch, slide.moveToProject")

        return registry
    }
}

// MARK: - Dependency Setup

public struct CommandRegistryKey: DependencyKey {
    public static var liveValue: CommandRegistry = .setupForSlide()
}

public extension DependencyValues {
    var slideCommandRegistry: CommandRegistry {
        get { self[CommandRegistryKey.self] }
        set { self[CommandRegistryKey.self] = newValue }
    }
}

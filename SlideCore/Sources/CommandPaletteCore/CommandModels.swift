import Foundation
import SwiftUI

// MARK: - Scope & Context

public enum PaletteScope: Hashable, Sendable {
    case cmdL, cmdT, cmdK, cmdP, cmdShiftP

    public var allowsWebResults: Bool {
        switch self {
        case .cmdL, .cmdT: return true
        default: return false
        }
    }
}

public struct PaletteContext: Equatable, Sendable {
    public var currentObjectID: String?
    public var selectionIDs: [String]
    public var route: String
    public var scopeProjectId: String?
    public var scopeProjectName: String?

    public init(currentObjectID: String? = nil, selectionIDs: [String] = [], route: String = "root") {
        self.currentObjectID = currentObjectID
        self.selectionIDs = selectionIDs
        self.route = route
    }
}

// MARK: - Command/Core Models

public struct CommandID: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum CommandEffect: Sendable, Equatable {
    case openURL(String)
    case updateCurrentURL(String)
    case selectTask(String)
    case openTask(String)
    case showSettings
    case toggleDarkMode
    case custom(String, payload: [String: String] = [:])
}

public struct CommandItem: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: String? // systemName, emoji, asset:Name, or remote URL
    public var metadata: String? // e.g. "2h ago"
    public var transition: CommandTransitionSpec

    public init(id: String, title: String, subtitle: String? = nil, icon: String? = nil, metadata: String? = nil, transition: CommandTransitionSpec) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.metadata = metadata
        self.transition = transition
    }
}

public enum CommandPaneKind: Sendable, Equatable {
    case list(providerID: String? = nil)
    case input(TextInputSpec, actionKey: String)
}

public struct TextInputSpec: Sendable, Equatable {
    public var title: String
    public var placeholder: String
    public var initial: String
    public init(title: String, placeholder: String, initial: String = "") {
        self.title = title
        self.placeholder = placeholder
        self.initial = initial
    }
}

public struct CommandPane: Identifiable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var title: String
    public var kind: CommandPaneKind
    public var items: [CommandItem] = []
    // For static lists, keep a copy of the original items to support proper filtering resets
    public var sourceItems: [CommandItem]? = nil
    public var query: String = ""
    public var selectedIndex: Int = 0

    public init(title: String, kind: CommandPaneKind, items: [CommandItem] = [], sourceItems: [CommandItem]? = nil) {
        self.title = title
        self.kind = kind
        self.items = items
        self.sourceItems = sourceItems
    }
}

// MARK: - Providers

public protocol CommandProvider: Sendable {
    /// Start streaming items for the given query and context.
    func start(query: String?, context: PaletteContext) -> AsyncStream<[CommandItem]>
}

// MARK: - Command Definition

public enum CommandTransitionSpec: Sendable, Equatable {
    case pushPane(CommandPaneSpec)
    case pushStaticList(title: String, items: [CommandItem])
    case effect(CommandEffect)
}

public struct CommandPaneSpec: Sendable, Equatable {
    public var title: String
    public var kind: CommandPaneKind
    public init(title: String, kind: CommandPaneKind) {
        self.title = title
        self.kind = kind
    }
}

public enum CommandStepSpec: Sendable, Equatable {
    case input(TextInputSpec, actionKey: String) // on submit -> delegate effect with key + value
    case list(providerID: String)
}

public enum CommandEntrySpec: Sendable, Equatable {
    case direct(effect: CommandEffect)
    case withProvider(title: String, providerID: String)
    case workflow(title: String, steps: [CommandStepSpec])
}

public struct CommandDefinition: Sendable {
    public let id: CommandID
    public let title: String
    public let keywords: [String]
    public let activation: @Sendable (PaletteContext, PaletteScope) -> Bool
    public let entry: CommandEntrySpec
    public let icon: String?
    public let shortcut: String?

    public init(id: CommandID, title: String, keywords: [String] = [], icon: String? = nil, shortcut: String? = nil, activation: @escaping @Sendable (PaletteContext, PaletteScope) -> Bool, entry: CommandEntrySpec) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.activation = activation
        self.entry = entry
        self.icon = icon
        self.shortcut = shortcut
    }
}

// MARK: - Registry

public final class CommandRegistry: @unchecked Sendable {
    private(set) public var commands: [CommandDefinition] = []
    private var providers: [String: any CommandProvider] = [:]

    public init() {}

    public func register(_ defs: CommandDefinition...) { commands += defs }
    public func register(commands defs: [CommandDefinition]) { commands += defs }

    public func registerProvider(id: String, provider: any CommandProvider) {
        providers[id] = provider
    }

    public func provider(for id: String) -> (any CommandProvider)? { providers[id] }

    public func eligible(for ctx: PaletteContext, scope: PaletteScope) -> [CommandDefinition] {
        commands.filter { $0.activation(ctx, scope) }
    }
}
